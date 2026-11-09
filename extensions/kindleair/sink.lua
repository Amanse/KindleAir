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
void *gst_bin_get_by_name(void *, const char *);
void *gst_query_new_position(int);
int gst_element_query(void *, void *);
void gst_query_parse_position(void *, int *, int64_t *);
void gst_mini_object_unref(void *);
int open(const char *, int, ...);
long read(int, void *, unsigned long);
int close(int);
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
local source = 'fdsrc name=pcm_source fd=0 blocksize=4096'
local anchor = -1
if arg[1] == 'stream' then
 assert(arg[2] and arg[2]:match('^/tmp/kindleair%.[%w]+/audio$'), 'Invalid PCM pipe path')
 anchor = ffi.C.open(arg[2], 2050) -- Linux O_RDWR|O_NONBLOCK
 assert(anchor >= 0, 'Cannot open PCM pipe')
 source = 'fdsrc name=pcm_source blocksize=4096 fd=' .. tonumber(anchor)
 log('reading PCM pipe ' .. arg[2])
end
local pipeline = gst.gst_parse_launch(source .. ' ! ' .. caps .. ' ! queue max-size-time=0 max-size-bytes=16384 max-size-buffers=4 leaky=downstream ! mixersink', err)
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
local control = '/tmp/kindleair-control'
local pcm = gst.gst_bin_get_by_name(pipeline, 'pcm_source')
local last_position, last_audio = nil, nil
local function uptime()
 local f = assert(io.open('/proc/uptime', 'r'))
 local value = tonumber(f:read('*n')); f:close()
 return math.floor(value)
end
-- The supervisor removes the control directory while shutting down. A state
-- write that loses that race must not abort the audio helper.
local function write_state(name, value)
 local f = io.open(control .. '/' .. name .. '.new', 'w')
 if not f then return false end
 f:write(value, '\n'); f:close()
 if not os.rename(control .. '/' .. name .. '.new', control .. '/' .. name) then
  os.remove(control .. '/' .. name .. '.new')
  return false
 end
 return true
end
local function media_progress()
 if pcm == nil then return end
 local query = gst.gst_query_new_position(2) -- GST_FORMAT_BYTES
 local valid = gst.gst_element_query(pcm, query)
 if valid ~= 0 then
  local format, pos = ffi.new('int[1]'), ffi.new('int64_t[1]')
  gst.gst_query_parse_position(query, format, pos)
  local position, now = tonumber(pos[0]), uptime()
  if position >= 0 then
   if last_position == nil or position ~= last_position then last_audio = now end
   last_position = position
   write_state('media-state', now .. ' ' .. last_audio .. ' ' .. position)
  else os.remove(control .. '/media-state') end
 else os.remove(control .. '/media-state') end
 gst.gst_mini_object_unref(query)
end
-- Keep a reader open across resets so the producer cannot receive SIGPIPE.
-- fdsrc uses interruptible polling; it can stop even while the sender is paused.
local function resync()
 os.remove(control .. '/resync.request')
 log('resync: resetting firmware mixer and discarding queued PCM')
 assert(gst.gst_element_set_state(pipeline, 1) ~= 0, 'Mixer reset failed')
 local discarded = 0
 if anchor >= 0 then
  local buf = ffi.new('char[4096]')
  while discarded < 1048576 do
   local n = tonumber(ffi.C.read(anchor, buf, 4096))
   if n <= 0 then break end
   discarded = discarded + n
  end
 end
 last_position, last_audio = nil, uptime()
 assert(gst.gst_element_set_state(pipeline, 4) ~= 0, 'Mixer restart failed')
 write_state('resync.done', uptime() .. ' ' .. discarded)
 log('resync complete; discarded ' .. discarded .. ' PCM bytes')
end
while true do
 local request = io.open(control .. '/resync.request', 'r')
 if request then request:close(); resync() end
 media_progress()
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
