# Fixture: aijs_hostile

Populated with shell/JSON/YAML injection payloads (`$(touch ...)`, backticks, `'''`, quotes,
backslashes, colons, `${IFS}`, a 10k-char field). `scoutica import aijs` must land every value as
a LITERAL JSON/YAML string, create schema-valid output (or abort cleanly), and execute NOTHING.
The `aijs_pwned_canary*` tokens must never become files.
