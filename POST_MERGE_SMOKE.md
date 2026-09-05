# Post-merge main smoke

This temporary smoke PR exists only to run the existing P0 + P0.1 + P1 browser acceptance chain against the integrated `main` code at `38622e06791aead946dd5287b7fda96af460bb5d`.

Runtime code is unchanged. The only functional CI change is retargeting the P1 workflow's pull_request base from the old stacked branch to `main`.
