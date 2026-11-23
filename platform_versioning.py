"""One platform version for Maven, npm and Python distributions."""
from configparser import ConfigParser
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

NS = '{http://maven.apache.org/POM/4.0.0}'
PYTHON_MODULE = 'lareferencia-metadata-tools'
PYTHON_RELEASE = re.compile(r'(\d+\.\d+\.\d+)(?:-rc\.?(\d+))?(-SNAPSHOT)?')
BUILD_VERSION = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$')


def read_version(root):
    version = ET.parse(root / 'pom.xml').getroot().findtext(NS + 'version')
    if not version or not BUILD_VERSION.fullmatch(version):
        raise RuntimeError('The platform parent must declare a literal npm-compatible version.')
    return version


def active_modules(root):
    """The Maven reactor defines the active set, including frontend profiles."""
    tree = ET.parse(root / 'pom.xml').getroot()
    elements = tree.findall(NS + 'modules/' + NS + 'module')
    elements += tree.findall(NS + 'profiles/' + NS + 'profile/' + NS + 'modules/' + NS + 'module')
    modules = []
    for element in elements:
        name = (element.text or '').strip()
        path = Path(name)
        if not name or path.is_absolute() or '..' in path.parts:
            raise RuntimeError(f'Invalid reactor module path: {name}')
        if path.name == 'vufind' or path.name.startswith('lareferencia-contrib-'):
            continue
        if name not in modules:
            modules.append(name)
    return modules


def _replace_own_version(text, old_version, version):
    chunks = re.split(r'(<parent>.*?</parent>)', text, flags=re.S)
    for i in range(0, len(chunks), 2):
        chunks[i], count = re.subn(r'<version>\s*' + re.escape(old_version) + r'\s*</version>',
                                  f'<version>{version}</version>', chunks[i], count=1)
        if count:
            return ''.join(chunks)
    raise RuntimeError('Could not update the parent project version.')


def python_module(root):
    manifest = ConfigParser(interpolation=None)
    manifest.read(root / 'workspace.ini', encoding='utf-8')
    section = f'module.{PYTHON_MODULE}'
    if manifest.has_section(section):
        name = manifest.get(section, 'path', fallback=PYTHON_MODULE)
        path = Path(name)
        if not path.parts or path.is_absolute() or '..' in path.parts:
            raise RuntimeError(f'Invalid Python module path: {name}')
        return name
    return None


def versioned_modules(root):
    names = active_modules(root)
    python = python_module(root)
    return names + [python] if python is not None else names


def python_distribution_version(version):
    release = PYTHON_RELEASE.fullmatch(version)
    if release is None:
        raise RuntimeError('Python metadata tools require a stable, RC or SNAPSHOT platform version.')
    base, candidate, snapshot = release.groups()
    if candidate is not None:
        base += f'rc{int(candidate)}'
    return base + '.dev0' if snapshot else base


def python_version_change(project, version):
    if not project.is_file():
        raise RuntimeError(f'Missing {project}; initialize the workspace first.')
    text = project.read_text(encoding='utf-8')
    section = re.search(r'^\[project\][ \t]*\n.*?(?=^\[|\Z)', text, re.M | re.S)
    if section is None:
        raise RuntimeError(f'{project}: missing [project] table.')
    updated, count = re.subn(r"""^(version[ \t]*=[ \t]*)(['"])[^'"]*\2([ \t]*(?:\#.*)?)$""",
                             lambda m: f'{m[1]}{m[2]}{version}{m[2]}{m[3]}', section[0], flags=re.M)
    if count != 1:
        raise RuntimeError(f'{project}: declare one literal [project] version.')
    return text[:section.start()] + updated + text[section.end():]


def version_changes(root, version):
    """Validate the whole active set before writing any file; never traverse legacy clones."""
    if not BUILD_VERSION.fullmatch(version):
        raise RuntimeError('Version must be compatible with Maven and npm semver.')
    root = Path(root)
    original = (root / 'pom.xml').read_text()
    parent = ET.fromstring(original)
    current = read_version(root)
    group = parent.findtext(NS + 'groupId')
    artifact = parent.findtext(NS + 'artifactId')
    names = active_modules(root)
    projects = {}
    for name in names:
        path = root / name / 'pom.xml'
        if not path.is_file():
            raise RuntimeError(f'Missing active module: {name}; initialize the workspace first.')
        projects[name] = ET.parse(path).getroot()
    coordinates = {(t.findtext(NS + 'groupId') or group, t.findtext(NS + 'artifactId')) for t in projects.values()}
    managed = {}
    for dependency in parent.findall(NS + 'dependencyManagement/' + NS + 'dependencies/' + NS + 'dependency'):
        key = (dependency.findtext(NS + 'groupId'), dependency.findtext(NS + 'artifactId'))
        managed[key] = dependency.findtext(NS + 'version')
    for key in coordinates:
        if managed.get(key) != '${project.version}':
            raise RuntimeError(f'Parent dependencyManagement must manage {key[1]} with ${{project.version}}.')
    changes = {}
    if current != version:
        changes[root / 'pom.xml'] = _replace_own_version(original, current, version)
    for name, project in projects.items():
        pom = root / name / 'pom.xml'
        p = project.find(NS + 'parent')
        if p is None or p.findtext(NS + 'groupId') != group or p.findtext(NS + 'artifactId') != artifact:
            raise RuntimeError(f'{name} must inherit from {group}:{artifact}.')
        if project.find(NS + 'version') is not None:
            raise RuntimeError(f'{name} must inherit its version; remove its project <version>.')
        relative = p.findtext(NS + 'relativePath', '../pom.xml')
        if not relative or (pom.parent / relative).resolve() != (root / 'pom.xml').resolve():
            raise RuntimeError(f'{name}: parent relativePath must resolve to the workspace pom.xml.')
        for dependency in project.findall('.//' + NS + 'dependency'):
            key = (dependency.findtext(NS + 'groupId'), dependency.findtext(NS + 'artifactId'))
            if key in coordinates and dependency.find(NS + 'version') is not None:
                raise RuntimeError(f'{name}: internal dependency {key[1]} must use parent dependencyManagement.')
        if p.findtext(NS + 'version') != version:
            text = pom.read_text()
            block = re.search(r'<parent>.*?</parent>', text, re.S)
            replacement, count = re.subn(r'<version>[^<]+</version>', f'<version>{version}</version>', block[0], count=1)
            if count != 1:
                raise RuntimeError(f'{name}: parent version is missing.')
            changes[pom] = text[:block.start()] + replacement + text[block.end():]
        for package_dir in [pom.parent, pom.parent / 'angular', pom.parent / 'web']:
            for filename in ['package.json', 'package-lock.json']:
                path = package_dir / filename
                if not path.is_file():
                    continue
                data = json.loads(path.read_text())
                package_root = data.get('packages', {}).get('')
                if data.get('version') == version and (package_root is None or package_root.get('version') == version):
                    continue
                data['version'] = version
                if package_root is not None:
                    package_root['version'] = version
                changes[path] = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
    python = python_module(root)
    if python is not None:
        project = root / python / 'pyproject.toml'
        updated = python_version_change(project, python_distribution_version(version))
        if updated != project.read_text(encoding='utf-8'):
            changes[project] = updated
    return changes


def set_platform_version(root, version):
    changes = version_changes(root, version)
    for path, text in changes.items():
        path.write_text(text)
    return changes
