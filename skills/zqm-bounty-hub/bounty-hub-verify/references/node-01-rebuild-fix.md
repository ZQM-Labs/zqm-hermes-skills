# Node-01 indexer rebuild fix notes

Lock path: C:\Users\zqmco\.zqm-node-01-indexer\index\MAIN_WRITELOCK
Safe removal only when no indexer process is running.
After removal, retry /api/index with {"rebuild": true}.
App.py patch: _start_background_update now accepts rebuild flag and passes it through to _run_background_update.
