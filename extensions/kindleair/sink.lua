-- KindleAir: use the firmware GStreamer mixer without loading Alpine libraries.
local ffi = require('ffi')
local function log(s) io.stderr:write('Audio helper: ' .. s .. '\n'); io.stderr:flush() end
log('starting')
ffi.cdef[[
typedef struct { unsigned int domain; int code; char *message; } GError;
void gst_init(int *, char ***);
void *gst_parse_launch(const char *, GError **);
int gst_element_set_state(void *, int);
void *gst_element_get_bus(void *);
void *gst_bus_timed_pop_filtered(void *, uint64_t, unsigned int);
void gst_message_parse_error(void *, GError **, char **);
void gst_object_unref(void *);
void g_error_free(GError *);
void g_free(void *);
]]
local gst, version
for _, v in ipairs({'0.10', '1.0'}) do
 local ok, lib = pcall(ffi.load, 'libgstreamer-' .. v .. '.so.0')
 if ok then gst, version = lib, v; break end
end
assert(gst, 'No firmware GStreamer 0.10/1.0 library found')
log('loaded firmware GStreamer ' .. version)
gst.gst_init(nil, nil)
log('GStreamer initialized')
local caps = version == '0.10'
 and 'audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=44100,channels=2'
 or 'audio/x-raw,format=S16LE,layout=interleaved,rate=44100,channels=2'
local err = ffi.new('GError *[1]')
local source = 'fdsrc fd=0 blocksize=4096'
if arg[1] == 'stream' then
 assert(arg[2] and arg[2]:match('^/tmp/kindleair%.[%w]+/audio$'), 'Invalid PCM pipe path')
 source = 'filesrc location=' .. string.format('%q', arg[2])
 log('reading PCM pipe ' .. arg[2])
end
local pipeline = gst.gst_parse_launch(source .. ' ! ' .. caps .. ' ! queue max-size-time=250000000 max-size-bytes=0 max-size-buffers=0 ! mixersink', err)
if err[0] ~= nil then error(ffi.string(err[0].message)) end
assert(pipeline ~= nil, 'Cannot build firmware mixersink pipeline')
if arg[1] == 'probe' then
 print('Firmware GStreamer ' .. version .. ': raw PCM -> mixersink pipeline available')
 gst.gst_object_unref(pipeline)
 return
end
log('requesting mixer PLAYING state')
local state = gst.gst_element_set_state(pipeline, 4)
log('mixer state result ' .. tonumber(state))
assert(state ~= 0, 'Firmware mixer refused PLAYING state')
local bus = gst.gst_element_get_bus(pipeline)
assert(bus ~= nil, 'Firmware mixer bus unavailable')
log('waiting for AirPlay audio')
while true do
 local msg = gst.gst_bus_timed_pop_filtered(bus, 1000000000, 2) -- ERROR only
 if msg ~= nil then
  local debugmsg = ffi.new('char *[1]')
  gst.gst_message_parse_error(msg, err, debugmsg)
  local text = err[0] ~= nil and ffi.string(err[0].message) or 'GStreamer error'
  io.stderr:write(text .. '\n')
  gst.gst_element_set_state(pipeline, 1)
  os.exit(1)
 end
end
