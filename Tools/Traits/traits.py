#!/usr/bin/env python3
"""Which of SwiftUIWeb's package traits an app needs (decision 0024).

On iOS, `import SwiftUI` brings `@FetchRequest` and `FetchedResults`, and `import Foundation`
brings `NSPredicate` and `NSSortDescriptor`. Here those live in WebCoreData, which the `SwiftUI`
module and the `Foundation` shadow re-export only when the app enables the `CoreData` trait on
the SwiftUIWeb and Shadows packages. `Decimal`'s formatting (`.formatted(.currency(code:))`) lives
in WebDecimalFormats, which the `Foundation` shadow re-exports only with the `DecimalFormatting`
trait on Shadows. Every other app's bundle leaves them out (decision 0006's size budget).

    Tools/Traits/traits.py <app-dir>                       # the traits it needs, with the evidence
    Tools/Traits/traits.py <app-dir> --check Package.swift # warn when the manifest leaves one off
"""
import argparse
import re
import sys
from pathlib import Path

SKIP_DIRS = {".build", ".git", ".swiftpm", "DerivedData", "Pods", "Carthage", "node_modules"}

# What makes an app need Core Data: a model bundle, or a Core Data name in its Swift sources.
CORE_DATA_NAMES = re.compile(
    r"@(?:Sectioned)?FetchRequest\b|\b(?:FetchedResults|SectionedFetchResults|NSFetchRequest|NSPredicate|"
    r"NSCompoundPredicate|NSComparisonPredicate|NSSortDescriptor|NSManagedObject(?:Context|ID|Model)?|"
    r"NSPersistentContainer|NSPersistentCloudKitContainer|NSEntityDescription|managedObjectContext)\b"
    r"|^\s*(?:@\w+\s+)*import\s+CoreData\b",
    re.MULTILINE,
)

# What makes an app need Decimal's formatting: `Decimal` in its Swift code. An app that names
# Decimal already links Foundation's Decimal; the formatting adds little beside it.
DECIMAL_NAMES = re.compile(r"\bDecimal\b")

# Each trait: what makes an app need it, and the packages the app enables it on.
TRAITS = {
    "CoreData": (CORE_DATA_NAMES, ("SwiftUIWeb", "Shadows"), "uses Core Data",
                 "files that import only SwiftUI or Foundation will not see @FetchRequest or NSPredicate"),
    "DecimalFormatting": (DECIMAL_NAMES, ("Shadows",), "uses Decimal",
                          "files that import Foundation will not see Decimal.formatted or Decimal.FormatStyle"),
}


def needed_in_text(text: str):
    """The traits a Swift file's code needs, as {trait: match}."""
    code = code_only(text)
    found = {}
    for trait, (names, _, _, _) in TRAITS.items():
        match = names.search(code)
        if match:
            found[trait] = (code, match)
    return found


def code_only(text: str) -> str:
    """The Swift source without its string literals and comments (names in them do not count);
    line breaks stay, so line numbers do."""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group(0))
    text = re.sub(r'#*"""[\s\S]*?"""#*', blank, text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', blank, text)
    text = re.sub(r"/\*[\s\S]*?\*/", blank, text)
    return re.sub(r"//[^\n]*", blank, text)


def _files(root: Path):
    for path in sorted(root.rglob("*")):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        yield path


def needed(root: Path):
    """{trait: [evidence]} for the app under `root`."""
    evidence = {}
    for path in _files(root):
        rel = path.relative_to(root)
        if path.is_dir() and path.suffix in (".xcdatamodeld", ".xcdatamodel"):
            if not (path.suffix == ".xcdatamodel" and path.parent.suffix == ".xcdatamodeld"):
                evidence.setdefault("CoreData", []).append(f"{rel}: a Core Data model")
        elif path.suffix == ".swift" and path.is_file():
            for trait, (code, match) in needed_in_text(path.read_text(errors="replace")).items():
                line = code.count("\n", 0, match.start()) + 1
                evidence.setdefault(trait, []).append(f"{rel}:{line}: {match.group(0).strip()}")
    return {trait: evidence[trait] for trait in TRAITS if trait in evidence}


def enabled(manifest: str, trait: str, package: str):
    """Whether the manifest's dependency on `package` lists `trait` (a literal `traits:` list)."""
    for m in re.finditer(r"\.package\(([^()]*(?:\([^()]*\)[^()]*)*)\)", manifest):
        body = m.group(1)
        if re.search(rf'name:\s*"{package}"', body) or re.search(rf'path:\s*"[^"]*{package}"', body):
            if re.search(rf'traits:\s*\[[^\]]*"{trait}"', body):
                return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("app")
    parser.add_argument("--check", metavar="MANIFEST")
    args = parser.parse_args()
    traits = needed(Path(args.app))
    if not args.check:
        for trait, evidence in traits.items():
            print(trait)
            for e in evidence[:5]:
                print(f"  {e}")
            if len(evidence) > 5:
                print(f"  ...and {len(evidence) - 5} more")
        return 0
    manifest = Path(args.check).read_text()
    for trait, evidence in traits.items():
        _, packages, uses, effect = TRAITS[trait]
        missing = [p for p in packages if not enabled(manifest, trait, p)]
        if missing:
            where = " and ".join('.package(name: "%s", ...)' % p for p in missing)
            print('warning: %s %s (%s), but %s does not enable the "%s" trait on %s; %s. Add '
                  'traits: ["%s"] to %s (decision 0024).'
                  % (args.app, uses, evidence[0], args.check, trait, " and ".join(missing), effect, trait, where),
                  file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
