#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <new-version>" >&2
  echo "Example: $0 5.0.0-rc3" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
new_version="$1"
[[ "$new_version" =~ ^[0-9][A-Za-z0-9._+-]*$ ]] || usage
command -v mvn >/dev/null 2>&1 || { echo 'mvn is required in PATH' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'python3 is required in PATH' >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
current_version="$(python3 - "${script_dir}/pom.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
namespace = '{http://maven.apache.org/POM/4.0.0}'
print(root.findtext(namespace + 'version', '').strip())
PY
)"
[[ -n "${current_version}" ]] || { echo 'Could not read the current parent version' >&2; exit 1; }

echo "Updating Maven reactor to ${new_version}..."
mvn -f "${script_dir}/pom.xml" versions:set "-DnewVersion=${new_version}"

# These projects are included in the reactor but have independent Maven
# coordinates, so the parent reactor does not change their own project version.
standalone_modules=(
  lareferencia-lrharvester-admin-web
  lareferencia-repository-dashboard
  lareferencia-oai-pmh
)
for module in "${standalone_modules[@]}"; do
  pom="${script_dir}/${module}/pom.xml"
  [[ -f "${pom}" ]] || continue
  echo "Updating independent module ${module} to ${new_version}..."
  mvn -N -f "${pom}" versions:set "-DnewVersion=${new_version}"
done

# Dashboard REST is retired and is not part of the Maven reactor. Keep its
# inherited parent and matching platform dependency aligned without asking the
# Versions plugin to set a project version that it inherits from its parent.
# Also keep the Angular package metadata aligned with its Maven project.
python3 - "${current_version}" "${new_version}" "${script_dir}" <<'PY'
import json
import sys
from pathlib import Path

old_version, version, root = sys.argv[1], sys.argv[2], Path(sys.argv[3])
legacy_pom = root / 'lareferencia-dashboard-rest' / 'pom.xml'
if legacy_pom.is_file():
    text = legacy_pom.read_text()
    legacy_pom.write_text(text.replace(old_version, version))

package_dir = root / 'lareferencia-repository-dashboard' / 'angular'
for filename in (package_dir / 'package.json', package_dir / 'package-lock.json'):
    if not filename.is_file():
        continue
    data = json.loads(filename.read_text())
    data['version'] = version
    if filename.name == 'package-lock.json' and '' in data.get('packages', {}):
        data['packages']['']['version'] = version
    filename.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
PY

echo "Version update complete: ${new_version}"
