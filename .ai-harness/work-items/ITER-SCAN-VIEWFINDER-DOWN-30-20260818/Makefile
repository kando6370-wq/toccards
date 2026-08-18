.PHONY: scan-goldens scan-position-test scan-test analyze

FLUTTER_TOOL = FLUTTER_ALREADY_LOCKED=true /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart /opt/homebrew/share/flutter/bin/cache/flutter_tools.snapshot

scan-goldens:
	$(FLUTTER_TOOL) test --no-pub --update-goldens --name 'Figma (scan pre-scan|scan scanning|recognition|scan reveal) renders at the 390x844 baseline' test/widget/scan_page_test.dart

scan-position-test:
	$(FLUTTER_TOOL) test --no-pub --name '(Camera recognition uses the yellow viewfinder|Recognition mask matches the visible viewfinder|Figma (scan pre-scan|scan scanning|recognition|scan reveal) renders at the 390x844 baseline)' test/widget/scan_page_test.dart

scan-test:
	$(FLUTTER_TOOL) test --no-pub test/widget/scan_page_test.dart

analyze:
	$(FLUTTER_TOOL) analyze --no-pub
