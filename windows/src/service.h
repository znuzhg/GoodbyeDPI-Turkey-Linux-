// Windows service management functions for GoodbyeDPI
// service_register: 1 = started as service, 0 = interactive launch, -1 = dispatch/setup failure
int service_register(int argc, char *argv[]);
void service_main(int argc, char *argv[]);       // Service entry point called by Windows
void service_report_running(void);               // Report RUNNING after packet filters are ready
void service_controlhandler(DWORD request);      // Handle service control events (stop/shutdown)
