#ifndef RUNNER_WINDOW_RECORD_H_
#define RUNNER_WINDOW_RECORD_H_

// Reads the record the app wrote in its last run from window_size.txt in the
// app data directory, and writes it into |width|, |height| and |maximized|.
// Returns false when there is nothing to read — a file that is not there,
// cannot be read, is not four whole numbers, is not the version the app
// writes, or has a state that is not one of the two the app writes — and
// leaves them as they are. Those are the same rules the app's own reader
// follows (`ai/doc.md` §7), so a line one reader rejects is rejected by the
// other. Nothing is reported for any of them: a record that cannot be read is
// not something the runner can show, and a run that starts at the default size
// is not an error.
//
// The numbers are the size as the app read it from the window, which on
// Windows is physical pixels — what CreateWindow takes — so the caller uses
// them as they are. A record that says maximized is the state the window is
// created in, and the size is then what it restores to, since Windows restores
// a window to the size it was created with.
bool ReadRecordedRecord(int* width, int* height, bool* maximized);

#endif  // RUNNER_WINDOW_RECORD_H_
