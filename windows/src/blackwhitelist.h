// Load domains from list file (TRUE on success, FALSE on failure)
int blackwhitelist_load_list(const char *filename);

// Check hostname against list, returns match status
int blackwhitelist_check_hostname(const char *host_addr, size_t host_len);
