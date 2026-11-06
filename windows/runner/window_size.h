#ifndef RUNNER_WINDOW_SIZE_H_
#define RUNNER_WINDOW_SIZE_H_

#include <string>

// Reads the size the app recorded in its last run from window_size.txt in the
// app data directory, and writes it into |width| and |height>. Returns false
// when there is nothing to read: a file that is not there, cannot be read, is
// not three whole numbers, or is not the version the app writes. Those are the
// same rules the app's own reader follows (`ai/doc.md` §7), so a line one
// reader rejects is rejected by the other. Nothing is reported for any of them:
// a size that cannot be read is not something the runner can show, and a run
// that starts at the default size is not an error.
//
// The numbers are the size as the app read it from the window, which on Windows
// is physical pixels — what CreateWindow takes — so the caller uses them as
// they are.
bool ReadRecordedSize(int* width, int* height);

#endif  // RUNNER_WINDOW_SIZE_H_
