#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "goodbyedpi.h"
#include "service.h"

#define SERVICE_NAME "GoodbyeDPI"

static SERVICE_STATUS ServiceStatus;
static SERVICE_STATUS_HANDLE hStatus;
static int service_argc = 0;
static char **service_argv = NULL;

/*
 * Returns 1 when the process was dispatched as a service, 0 when launched
 * interactively, and -1 for a real service-dispatch/setup failure.
 */
int service_register(int argc, char *argv[])
{
    int i;
    BOOL dispatched;

    SERVICE_TABLE_ENTRY ServiceTable[] = {
        {SERVICE_NAME, (LPSERVICE_MAIN_FUNCTION)service_main},
        {NULL, NULL}
    };

    if (argc <= 0 || !argv)
        return -1;

    service_argv = calloc((size_t)argc + 1, sizeof(*service_argv));
    if (!service_argv)
        return -1;

    for (i = 0; i < argc; i++) {
        if (!argv[i] || !(service_argv[i] = strdup(argv[i]))) {
            while (i > 0)
                free(service_argv[--i]);
            free(service_argv);
            service_argv = NULL;
            return -1;
        }
    }
    service_argc = argc;

    dispatched = StartServiceCtrlDispatcher(ServiceTable);
    if (!dispatched) {
        DWORD error = GetLastError();
        /* ERROR_FAILED_SERVICE_CONTROLLER_CONNECT means console/interactive launch. */
        i = (error == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT) ? 0 : -1;
    }
    else {
        i = 1;
    }

    for (int j = 0; j < service_argc; j++)
        free(service_argv[j]);
    free(service_argv);
    service_argv = NULL;
    service_argc = 0;

    return i;
}

void service_main(int argc __attribute__((unused)),
                  char *argv[] __attribute__((unused)))
{
    memset(&ServiceStatus, 0, sizeof(ServiceStatus));
    ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    ServiceStatus.dwCurrentState = SERVICE_START_PENDING;
    ServiceStatus.dwControlsAccepted = 0;
    ServiceStatus.dwWin32ExitCode = NO_ERROR;
    ServiceStatus.dwWaitHint = 10000;
    ServiceStatus.dwCheckPoint = 1;

    hStatus = RegisterServiceCtrlHandler(SERVICE_NAME,
                                         (LPHANDLER_FUNCTION)service_controlhandler);
    if (!hStatus)
        return;

    SetServiceStatus(hStatus, &ServiceStatus);

    /* Run the original command line captured before service dispatch. */
    ServiceStatus.dwWin32ExitCode = (DWORD)main(service_argc, service_argv);
    ServiceStatus.dwCurrentState = SERVICE_STOPPED;
    ServiceStatus.dwControlsAccepted = 0;
    ServiceStatus.dwCheckPoint = 0;
    ServiceStatus.dwWaitHint = 0;
    SetServiceStatus(hStatus, &ServiceStatus);
}

/*
 * Called by main() after all WinDivert handles have been initialized.
 * Until then the service remains START_PENDING and does not accept stop
 * controls that could race filter creation.
 */
void service_report_running(void)
{
    if (!hStatus || ServiceStatus.dwCurrentState != SERVICE_START_PENDING)
        return;

    ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    ServiceStatus.dwCheckPoint = 0;
    ServiceStatus.dwWaitHint = 0;
    SetServiceStatus(hStatus, &ServiceStatus);
}

void service_controlhandler(DWORD request)
{
    switch (request) {
        case SERVICE_CONTROL_STOP:
        case SERVICE_CONTROL_SHUTDOWN:
            if (ServiceStatus.dwCurrentState == SERVICE_RUNNING) {
                /* The service main thread reports STOPPED after its receive loop exits. */
                ServiceStatus.dwCurrentState = SERVICE_STOP_PENDING;
                ServiceStatus.dwControlsAccepted = 0;
                ServiceStatus.dwCheckPoint = 1;
                ServiceStatus.dwWaitHint = 5000;
                SetServiceStatus(hStatus, &ServiceStatus);
                deinit_all();
            }
            return;

        case SERVICE_CONTROL_INTERROGATE:
            break;

        default:
            return;
    }

    SetServiceStatus(hStatus, &ServiceStatus);
}
