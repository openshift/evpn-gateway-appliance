.PHONY: verify check

# Static source checks. The single entry point CI runs; add more as prerequisites.
verify: check

# Public-safety gate for this PUBLIC repository.
#
#   make check              full run (corpus link/pin checks need network + authenticated gh)
#   make check OFFLINE=1    skip the network/gh checks (link + pin resolution)
#   make check TERMS=path   also screen for customer/partner/account names listed in `path`
#                           (keep that file OUTSIDE the repo; never commit it)
#
# The corpus checkers (check-all.sh and friends) and check-public-safe.py are stdlib-only
# Python; they need just python3 plus curl/gh at runtime for the network checks.

TOOLS := plans/context/evpn-aws/tools
TERMS ?=

check:
	# 1. Corpus checkers over the planning docs: link + anchor + pin resolution,
	#    embedded-snippet tests, and public-safe (check-all.sh bundles them).
	$(TOOLS)/check-all.sh $(if $(OFFLINE),--offline,)
	# 2. Public-exposure scan over tracked and new-but-not-ignored files (emails, non-doc
	#    IPs, AWS account IDs, keys/tokens, secret assignments, internal links).
	#    --exclude-standard keeps gitignored local artifacts (generated inventory, keys)
	#    out. --allow-private skips RFC1918 lab addrs; annotate known-public values with
	#    an inline `public-safe: ok`.
	git ls-files -z -c -o --exclude-standard | xargs -0 -r python3 $(TOOLS)/check-public-safe.py --allow-private $(if $(TERMS),--terms $(TERMS),)
