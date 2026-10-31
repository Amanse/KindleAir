/* MIT licensed KindleAir glue. Only preloaded into our no-drop-root Avahi.
 * Avahi's runtime-directory setup still looks up its build-time account.
 * Supply that account with the invoking process's IDs, without /etc edits.
 */
typedef unsigned int uid_t;
typedef unsigned int gid_t;
struct passwd {
 char *pw_name, *pw_passwd;
 uid_t pw_uid; gid_t pw_gid;
 char *pw_gecos, *pw_dir, *pw_shell;
};
struct group { char *gr_name, *gr_passwd; gid_t gr_gid; char **gr_mem; };
extern uid_t getuid(void);
extern gid_t getgid(void);
extern void *dlsym(void *, const char *);
static int is_avahi(const char *s) {
 const char *wanted = "avahi";
 if (!s) return 0;
 while (*wanted && *s == *wanted) { s++; wanted++; }
 return *s == 0 && *wanted == 0;
}
struct passwd *getpwnam(const char *name) {
 static struct passwd account = {"avahi", "x", 0, 0, "KindleAir local Avahi", "/", "/bin/sh"};
 if (is_avahi(name)) { account.pw_uid=getuid(); account.pw_gid=getgid(); return &account; }
 struct passwd *(*next)(const char *) = (struct passwd *(*)(const char *))dlsym((void *)-1, "getpwnam");
 return next ? next(name) : (void *)0;
}
struct group *getgrnam(const char *name) {
 static char *members[] = {(void *)0};
 static struct group account = {"avahi", "x", 0, members};
 if (is_avahi(name)) { account.gr_gid=getgid(); return &account; }
 struct group *(*next)(const char *) = (struct group *(*)(const char *))dlsym((void *)-1, "getgrnam");
 return next ? next(name) : (void *)0;
}
