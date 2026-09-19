# Deployment status

The fork and coordinator passed isolated integration tests. The NixOS system
closure is being built; live activation has not yet been confirmed.

Applying the configuration restarts the T3 service hosting the implementation
conversation. A separate activation/verification job will record the final live
service result here so it does not depend on that conversation surviving restart.
