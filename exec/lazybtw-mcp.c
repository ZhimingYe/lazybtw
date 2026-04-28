#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_SESSIONS 1024
#define MAX_READ (64 * 1024 * 1024)

typedef struct {
  char *session_id;
  char *project;
  char *dish_path;
  char *updated_at;
  long pid;
  int entries;
} session_t;

typedef struct { char *data; size_t len; size_t cap; } sbuf_t;

static void sb_init(sbuf_t *b) { b->cap = 4096; b->len = 0; b->data = malloc(b->cap); if (!b->data) exit(127); b->data[0] = '\0'; }
static void sb_reserve(sbuf_t *b, size_t add) {
  if (add > SIZE_MAX - b->len - 1) exit(127);
  size_t need = b->len + add + 1;
  if (need <= b->cap) return;
  while (need > b->cap) {
    if (b->cap > SIZE_MAX / 2) exit(127);
    b->cap *= 2;
  }
  char *next = realloc(b->data, b->cap);
  if (!next) exit(127);
  b->data = next;
}
static void sb_append_n(sbuf_t *b, const char *s, size_t n) { sb_reserve(b, n); memcpy(b->data + b->len, s, n); b->len += n; b->data[b->len] = '\0'; }
static void sb_append(sbuf_t *b, const char *s) { sb_append_n(b, s, strlen(s)); }
static void sb_printf(sbuf_t *b, const char *fmt, ...) { va_list ap; va_start(ap, fmt); va_list ap2; va_copy(ap2, ap); int n = vsnprintf(NULL, 0, fmt, ap); va_end(ap); if (n < 0) { va_end(ap2); return; } sb_reserve(b, (size_t)n); vsnprintf(b->data + b->len, b->cap - b->len, fmt, ap2); va_end(ap2); b->len += (size_t)n; }

static void json_escape_into(sbuf_t *b, const char *s) {
  if (!s) return;
  for (; *s; s++) {
    unsigned char c = (unsigned char)*s;
    switch (c) {
      case '"': sb_append(b, "\\\""); break;
      case '\\': sb_append(b, "\\\\"); break;
      case '\b': sb_append(b, "\\b"); break;
      case '\f': sb_append(b, "\\f"); break;
      case '\n': sb_append(b, "\\n"); break;
      case '\r': sb_append(b, "\\r"); break;
      case '\t': sb_append(b, "\\t"); break;
      default:
        if (c < 0x20) sb_printf(b, "\\u%04x", c); else sb_append_n(b, (const char *)&c, 1);
    }
  }
}
static char *json_escape(const char *s) { sbuf_t b; sb_init(&b); json_escape_into(&b, s); return b.data; }

static char *slurp_file(const char *path, size_t max) {
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
  long sz = ftell(f); if (sz < 0 || (size_t)sz > max) { fclose(f); return NULL; }
  rewind(f);
  char *buf = malloc((size_t)sz + 1); if (!buf) { fclose(f); return NULL; }
  size_t n = fread(buf, 1, (size_t)sz, f); fclose(f); buf[n] = '\0'; return buf;
}

static char *path_join2(const char *a, const char *b) { char *r = NULL; if (asprintf(&r, "%s/%s", a, b) < 0) exit(127); return r; }
static char *lazybtw_data_dir(void) {
  const char *env = getenv("LAZYBTW_DATA_DIR"); if (env && *env) return strdup(env);
  const char *home = getenv("HOME"); if (!home || !*home) home = ".";
  const char *xdg = getenv("XDG_DATA_HOME");
  char *candidate = NULL;
  if (xdg && *xdg) {
    if (asprintf(&candidate, "%s/lazybtw", xdg) < 0) exit(127);
    if (access(candidate, F_OK) == 0) return candidate;
    free(candidate);
  }
  if (asprintf(&candidate, "%s/.local/share/lazybtw", home) < 0) exit(127);
  if (access(candidate, F_OK) == 0) return candidate;
  free(candidate);
  // Compatibility with tools::R_user_dir("lazybtw", "data") on Linux.
  if (asprintf(&candidate, "%s/.local/share/R/lazybtw", home) < 0) exit(127);
  return candidate;
}

static bool safe_path(const char *path, bool must_file) {
  struct stat st; if (stat(path, &st) != 0) return false;
  if (st.st_uid != getuid()) return false;
  if ((st.st_mode & 0022) != 0) return false;
  if (must_file && !S_ISREG(st.st_mode)) return false;
  return true;
}

static char *json_find_key_value(const char *json, const char *key) {
  char pat[128]; snprintf(pat, sizeof(pat), "\"%s\"", key);
  char *p = (char *)json;
  while ((p = strstr(p, pat))) {
    char *q = p + strlen(pat);
    while (isspace((unsigned char)*q)) q++;
    if (*q == ':') return q + 1;
    p = q;
  }
  return NULL;
}

static char *json_get_string(const char *json, const char *key) {
  char *p = json_find_key_value(json, key);
  if (!p) return NULL;
  while (isspace((unsigned char)*p)) p++;
  if (strncmp(p, "null", 4) == 0) return NULL;
  if (*p != '"') return NULL;
  p++;
  sbuf_t b; sb_init(&b);
  while (*p && *p != '"') {
    if (*p == '\\') {
      p++;
      switch (*p) {
        case 'n': sb_append(&b, "\n"); break; case 'r': sb_append(&b, "\r"); break; case 't': sb_append(&b, "\t"); break;
        case 'b': sb_append(&b, "\b"); break; case 'f': sb_append(&b, "\f"); break;
        case '"': sb_append(&b, "\""); break; case '\\': sb_append(&b, "\\"); break; case '/': sb_append(&b, "/"); break;
        case 'u': sb_append(&b, "?"); p += 4; break;
        default: if (*p) sb_append_n(&b, p, 1);
      }
      if (*p) p++;
    } else { sb_append_n(&b, p, 1); p++; }
  }
  return b.data;
}

static long json_get_long(const char *json, const char *key, long def) {
  char *p = json_find_key_value(json, key);
  if (!p) return def;
  while (isspace((unsigned char)*p)) p++;
  char *end = NULL; long v = strtol(p, &end, 10); return end == p ? def : v;
}

static bool pid_alive(long pid) { if (pid <= 0) return false; return kill((pid_t)pid, 0) == 0 || errno == EPERM; }

static int count_lines_safe(const char *path) {
  if (!path || !safe_path(path, true)) return 0;
  FILE *f = fopen(path, "rb"); if (!f) return 0;
  int c, n = 0, any = 0;
  while ((c = fgetc(f)) != EOF) { any = 1; if (c == '\n') n++; }
  fclose(f); return any ? n : 0;
}

static void free_session(session_t *s) { free(s->session_id); free(s->project); free(s->dish_path); free(s->updated_at); memset(s, 0, sizeof(*s)); }
static int cmp_session(const void *a, const void *b) { const session_t *x=a, *y=b; const char *xu=x->updated_at?x->updated_at:"", *yu=y->updated_at?y->updated_at:""; return strcmp(yu, xu); }

static int load_sessions(session_t *out, int max) {
  char *base = lazybtw_data_dir(); char *sdir = path_join2(base, "sessions"); free(base);
  DIR *d = opendir(sdir); if (!d) { free(sdir); return 0; }
  int n = 0; struct dirent *de;
  while ((de = readdir(d)) && n < max) {
    size_t len = strlen(de->d_name); if (len < 6 || strcmp(de->d_name + len - 5, ".json") != 0) continue;
    char *path = path_join2(sdir, de->d_name); if (!safe_path(path, true)) { free(path); continue; }
    char *json = slurp_file(path, 1024 * 1024); free(path); if (!json) continue;
    session_t s = {0};
    s.session_id = json_get_string(json, "session_id");
    s.project = json_get_string(json, "project");
    s.dish_path = json_get_string(json, "dish_path");
    s.updated_at = json_get_string(json, "updated_at");
    s.pid = json_get_long(json, "pid", -1);
    free(json);
    if (!s.session_id || !s.dish_path || !safe_path(s.dish_path, true) || !pid_alive(s.pid)) { free_session(&s); continue; }
    s.entries = count_lines_safe(s.dish_path);
    out[n++] = s;
  }
  closedir(d); free(sdir); qsort(out, n, sizeof(session_t), cmp_session); return n;
}

static void append_text_tool_result(sbuf_t *json, const char *id, const char *text, bool is_error) {
  char *e = json_escape(text ? text : "");
  sb_printf(json, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}],\"isError\":%s}}", id, e, is_error ? "true" : "false");
  free(e);
}

static char **read_tail_lines(const char *path, int limit, int *out_n) {
  *out_n = 0; if (!path || !safe_path(path, true) || limit <= 0) return NULL;
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  char **ring = calloc((size_t)limit, sizeof(char*)); if (!ring) { fclose(f); return NULL; }
  char *line = NULL; size_t cap = 0; ssize_t nr; int total = 0;
  while ((nr = getline(&line, &cap, f)) != -1) {
    while (nr > 0 && (line[nr-1] == '\n' || line[nr-1] == '\r')) line[--nr] = '\0';
    if (nr == 0) continue;
    int idx = total % limit; free(ring[idx]); ring[idx] = strdup(line); total++;
  }
  free(line); fclose(f);
  int n = total < limit ? total : limit; char **res = calloc((size_t)n, sizeof(char*)); if (!res) return ring;
  int start = total > limit ? total % limit : 0;
  for (int i = 0; i < n; i++) { int idx = (start + i) % limit; res[i] = ring[idx]; ring[idx] = NULL; }
  for (int i = 0; i < limit; i++) {
    free(ring[i]);
  }
  free(ring);
  *out_n = n;
  return res;
}

static void append_markdown_context(sbuf_t *b, const session_t *s, int limit) {
  sb_append(b, "# R language context\n\n");
  sb_printf(b, "Session: %s\n", s->session_id ? s->session_id : "");
  sb_printf(b, "Project: %s\n", s->project ? s->project : "");
  sb_printf(b, "PID: %ld\n", s->pid);
  sb_printf(b, "Updated: %s\n\n", s->updated_at ? s->updated_at : "");
  sb_append(b, "## Recent context\n\n");
  int n = 0; char **lines = read_tail_lines(s->dish_path, limit, &n);
  if (!n) { sb_append(b, "No lazybtw dish context has been recorded yet."); free(lines); return; }
  for (int i = n - 1, k = 1; i >= 0; i--, k++) {
    char *source = json_get_string(lines[i], "source"); char *kind = json_get_string(lines[i], "kind"); char *time = json_get_string(lines[i], "time"); char *label = json_get_string(lines[i], "label"); char *text = json_get_string(lines[i], "text");
    sb_printf(b, "### %d. %s / %s / %s", k, source?source:"unknown", kind?kind:"text", time?time:"");
    if (label && *label) sb_printf(b, " / %s", label);
    sb_append(b, "\n\n```\n"); sb_append(b, text?text:""); sb_append(b, "\n```\n\n");
    free(source); free(kind); free(time); free(label); free(text); free(lines[i]);
  }
  free(lines);
}

static char *get_method(const char *body) { return json_get_string(body, "method"); }
static char *json_get_id_literal(const char *json) {
  char *p = json_find_key_value(json, "id");
  if (!p) return NULL;
  while (isspace((unsigned char)*p)) p++;
  if (strncmp(p, "null", 4) == 0) return NULL;
  if (*p == '"') {
    char *value = json_get_string(json, "id");
    if (!value) return NULL;
    char *escaped = json_escape(value);
    free(value);
    char *literal = NULL;
    if (asprintf(&literal, "\"%s\"", escaped) < 0) exit(127);
    free(escaped);
    return literal;
  }
  char *end = p;
  if (*end == '-') end++;
  while (isdigit((unsigned char)*end)) end++;
  if (end == p || (end == p + 1 && *p == '-')) return NULL;
  return strndup(p, (size_t)(end - p));
}

static char *response_initialize(const char *id) {
  char *r=NULL; asprintf(&r, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"lazybtw\",\"version\":\"c-mcp\"}}}", id); return r;
}
static char *response_tools_list(const char *id) {
  char *r=NULL; asprintf(&r, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"tools\":[{\"name\":\"Inspect_R_lang_Context\",\"description\":\"Inspect recent read-only R analysis context recorded by lazybtw dish files.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"session_id\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\",\"default\":20,\"minimum\":1,\"maximum\":100}},\"additionalProperties\":false}},{\"name\":\"List_R_Sessions\",\"description\":\"List active R sessions with lazybtw dish context.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}}]}}", id); return r;
}

static char *response_tools_call(const char *id, const char *body) {
  char *name = json_get_string(body, "name"); sbuf_t resp; sb_init(&resp);
  if (!name) { append_text_tool_result(&resp, id, "Missing tool name", true); return resp.data; }
  session_t sessions[MAX_SESSIONS]; int n = load_sessions(sessions, MAX_SESSIONS);
  if (strcmp(name, "List_R_Sessions") == 0) {
    sbuf_t text; sb_init(&text); sb_append(&text, "# Active R sessions\n\n");
    if (!n) sb_append(&text, "No active lazybtw R sessions were found.");
    else {
      sb_append(&text, "| session_id | project | pid | updated_at | entries |\n|---|---|---:|---|---:|\n");
      for (int i=0;i<n;i++) sb_printf(&text, "| %s | %s | %ld | %s | %d |\n", sessions[i].session_id?sessions[i].session_id:"", sessions[i].project?sessions[i].project:"", sessions[i].pid, sessions[i].updated_at?sessions[i].updated_at:"", sessions[i].entries);
    }
    append_text_tool_result(&resp, id, text.data, false); free(text.data);
  } else if (strcmp(name, "Inspect_R_lang_Context") == 0) {
    char *sid = json_get_string(body, "session_id"); int limit = (int)json_get_long(body, "limit", 20); if (limit < 1) limit = 1; if (limit > 100) limit = 100;
    session_t *s = NULL; if (sid && *sid) { for (int i=0;i<n;i++) if (strcmp(sessions[i].session_id, sid)==0) { s=&sessions[i]; break; } } else if (n) s = &sessions[0];
    if (!s) append_text_tool_result(&resp, id, sid ? "No lazybtw R context session found with requested session_id." : "No lazybtw R context sessions were found. In R, run lazybtw::dish_start() and add context first.", false);
    else { sbuf_t text; sb_init(&text); append_markdown_context(&text, s, limit); append_text_tool_result(&resp, id, text.data, false); free(text.data); }
    free(sid);
  } else {
    append_text_tool_result(&resp, id, "Unknown tool", true);
  }
  for (int i = 0; i < n; i++) {
    free_session(&sessions[i]);
  }
  free(name);
  return resp.data;
}
static char *response_error(const char *id, int code, const char *msg) { char *e=json_escape(msg); char *r=NULL; asprintf(&r, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"error\":{\"code\":%d,\"message\":\"%s\"}}", id, code, e); free(e); return r; }

static char *handle(const char *body) {
  char *method = get_method(body);
  char *id = json_get_id_literal(body);
  char *r = NULL;
  if (!method) return NULL;
  if (!id) {
    free(method);
    return NULL;
  }
  if (strcmp(method, "initialize") == 0) r = response_initialize(id);
  else if (strcmp(method, "tools/list") == 0) r = response_tools_list(id);
  else if (strcmp(method, "tools/call") == 0) r = response_tools_call(id, body);
  else r = response_error(id, -32601, "Method not found");
  free(method);
  free(id);
  return r;
}

static void write_msg(const char *body) { printf("Content-Length: %zu\r\n\r\n%s", strlen(body), body); fflush(stdout); }

int main(void) {
  char line[4096];
  while (1) {
    long len = -1;
    while (fgets(line, sizeof(line), stdin)) {
      char *trimmed = line;
      while (isspace((unsigned char)*trimmed)) trimmed++;
      if (*trimmed == '{') {
        char *resp = handle(trimmed);
        if (resp) {
          printf("%s\n", resp);
          fflush(stdout);
          free(resp);
        }
        len = -2;
        break;
      }
      if (strcmp(line, "\r\n") == 0 || strcmp(line, "\n") == 0) break;
      if (strncasecmp(line, "Content-Length:", 15) == 0) len = strtol(line + 15, NULL, 10);
    }
    if (feof(stdin)) break;
    if (len == -2) continue;
    if (len <= 0 || len > MAX_READ) break;
    char *body = malloc((size_t)len + 1); if (!body) break;
    size_t got = fread(body, 1, (size_t)len, stdin);
    if (got > (size_t)len) got = (size_t)len;
    body[got] = '\0';
    if (got != (size_t)len) { free(body); break; }
    char *resp = handle(body); if (resp) { write_msg(resp); free(resp); }
    free(body);
  }
  return 0;
}
