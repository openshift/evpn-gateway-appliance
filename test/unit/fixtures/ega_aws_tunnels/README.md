# Tunnel fixtures

The XFRM fixtures preserve the text layout captured on x86 with Libreswan 5.4.1,
iproute2 7.0.0 and an EL10 6.12 kernel. Addresses use documentation networks;
all AEAD keys are the deliberately invalid `0xTEST_ONLY_EGA_XFRM_KEY` sentinel.
SPIs are synthetic. Foreign if_id 7 entries were added to check isolation.

`xfrm-policy.txt` adds synthetic indices in iproute2 7.0's `-s` layout to the
captured policies (including all socket and IPv6 ICMP defaults). The indices
allow deletion without reconstructing selectors. The template and link detail
lines retain the captured layout; optional lifetime statistics are omitted.
