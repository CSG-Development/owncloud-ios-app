//
//  TelemetryWrapper.h
//  telemetry
//
//  Created by Ken Sumrall on 2/18.
//  Copyright © 2018 seagate. All rights reserved.
//

#ifndef TelemetryWrapper_h
#define TelemetryWrapper_h

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

void TelemetryInit(const char* clientId, const char* requestType, const char* configJSON);
void TelemetrySend(const char* rType, const char* messageJSON);
void TelemetryFlush();

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif


