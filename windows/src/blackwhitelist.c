/*
 * Blacklist for GoodbyeDPI HTTP DPI circumvention tricks.
 * Hostname comparisons are case-insensitive, as required by DNS.
 */
#include <windows.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include "goodbyedpi.h"
#include "utils/uthash.h"
#include "utils/getline.h"

typedef struct blackwhitelist_record {
    const char *host;
    UT_hash_handle hh;
} blackwhitelist_record_t;

static blackwhitelist_record_t *blackwhitelist = NULL;

/* Normalize an ASCII DNS hostname in-place. Host headers may include :port. */
static int normalize_hostname(char *host, int strip_port) {
    size_t len;
    char *start;
    char *colon;

    if (!host)
        return FALSE;

    start = host;
    while (*start && isspace((unsigned char)*start))
        start++;
    if (start != host)
        memmove(host, start, strlen(start) + 1);

    len = strlen(host);
    while (len > 0 && isspace((unsigned char)host[len - 1]))
        host[--len] = '\0';

    if (strip_port) {
        /* Bracketed IPv6 literals are not domain names in this blacklist. */
        if (host[0] == '[')
            return FALSE;
        colon = strchr(host, ':');
        if (colon) {
            char *port = colon + 1;
            if (!*port)
                return FALSE;
            for (char *p = port; *p; p++) {
                if (*p < '0' || *p > '9')
                    return FALSE;
            }
            *colon = '\0';
        }
    }

    len = strlen(host);
    if (len > 0 && host[len - 1] == '.')
        host[--len] = '\0';
    if (len < 2 || len > HOST_MAXLEN)
        return FALSE;

    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)host[i];
        if (c > 0x7F)
            return FALSE;
        host[i] = (char)tolower(c);
    }

    return TRUE;
}

static int check_get_hostname(const char *host) {
    blackwhitelist_record_t *tmp_record = NULL;
    if (!blackwhitelist || !host)
        return FALSE;

    HASH_FIND_STR(blackwhitelist, host, tmp_record);
    if (tmp_record) {
        debug("check_get_hostname found host\n");
        return TRUE;
    }
    return FALSE;
}

static int add_hostname(const char *host) {
    char normalized[HOST_MAXLEN + 1];
    size_t len;
    blackwhitelist_record_t *tmp_record;
    char *host_copy;

    if (!host)
        return FALSE;

    len = strlen(host);
    if (len > HOST_MAXLEN)
        return FALSE;
    memcpy(normalized, host, len + 1);
    if (!normalize_hostname(normalized, FALSE))
        return FALSE;

    if (check_get_hostname(normalized))
        return FALSE;

    tmp_record = malloc(sizeof(*tmp_record));
    if (!tmp_record)
        return FALSE;

    host_copy = strdup(normalized);
    if (!host_copy) {
        free(tmp_record);
        return FALSE;
    }

    tmp_record->host = host_copy;
    HASH_ADD_KEYPTR(hh, blackwhitelist, tmp_record->host,
                    strlen(tmp_record->host), tmp_record);
    debug("Added host %s\n", host_copy);
    return TRUE;
}

/* Load domains from a newline-separated text file. Returns TRUE on success. */
int blackwhitelist_load_list(const char *filename) {
    size_t linelen = HOST_MAXLEN + 1;
    int count = 0;
    ssize_t read;
    FILE *fp;
    char *line;

    if (!filename)
        return FALSE;

    fp = fopen(filename, "r");
    if (!fp)
        return FALSE;

    line = malloc(HOST_MAXLEN + 1);
    if (!line) {
        fclose(fp);
        return FALSE;
    }

    while ((read = getline(&line, &linelen, fp)) != -1) {
        size_t len;
        (void)read;

        line[strcspn(line, "\r\n")] = '\0';
        len = strlen(line);
        if (len > HOST_MAXLEN) {
            printf("WARNING: host entry exceeds maximum length and was skipped\n");
            continue;
        }
        if (len == 0 || line[0] == '#' || line[0] == ';')
            continue;
        if (add_hostname(line))
            count++;
    }

    free(line);
    if (ferror(fp)) {
        fclose(fp);
        return FALSE;
    }

    fclose(fp);
    if (!blackwhitelist)
        return FALSE;

    printf("Loaded %d hosts from file %s\n", count, filename);
    return TRUE;
}

int blackwhitelist_check_hostname(const char *host_addr, size_t host_len) {
    char current_host[HOST_MAXLEN + 1];
    char *tokenized_host;

    if (!host_addr || host_len == 0 || host_len > HOST_MAXLEN)
        return FALSE;

    memcpy(current_host, host_addr, host_len);
    current_host[host_len] = '\0';
    if (!normalize_hostname(current_host, TRUE))
        return FALSE;

    if (check_get_hostname(current_host))
        return TRUE;

    tokenized_host = strchr(current_host, '.');
    while (tokenized_host) {
        if (check_get_hostname(tokenized_host + 1))
            return TRUE;
        tokenized_host = strchr(tokenized_host + 1, '.');
    }

    debug("____blackwhitelist_check_hostname FALSE: host %s\n", current_host);
    return FALSE;
}
