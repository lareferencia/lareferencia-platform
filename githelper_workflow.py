"""Branch coordination, immutable module locks and release version planning."""
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

LOCK = "workspace.lock"
VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-rc(?:\.?)(\d+))?$")


def checked(h, repo, *args):
    result = h.run_git(list(args), repo)
    if result.returncode:
        raise RuntimeError(f"{repo.name}: git {' '.join(args)}: {result.stderr}")
    return result.stdout


def clean(h, repo):
    if not h.is_git_repository(repo) or h.working_tree_status(repo) != "clean":
        raise RuntimeError(f"{repo}: repository must exist and be clean.")


def create_branches(h, args, include_parent):
    try:
        root = h.get_repo_root()
        workspace = h.load_workspace(root)
        modules = h.select_modules(workspace, args.modules)
        branch = args.branch or h.get_current_branch(root)
        if include_parent and not branch.startswith("codex/"):
            branch = "codex/" + branch
        if not branch or branch == "main":
            raise RuntimeError("Choose a feature branch, different from main.")
        checked(h, root, "check-ref-format", "--branch", branch)
        repos = ([root] if include_parent else []) + [root / m.path for m in modules]
        if include_parent:
            clean(h, root)
            parser = h.read_manifest_parser(root)
            section = f"branch-set.{branch}"
            if parser.has_section(section):
                raise RuntimeError(f"Branch-set already exists: {branch}")
        # Preflight every repository before creating any branch. Never reuse an
        # existing branch silently, nor carry uncommitted changes across bases.
        bases = []
        for repo in repos:
            clean(h, repo)
            checked(h, repo, "fetch", "--prune", "origin")
            if h.local_branch_exists(repo, branch) or h.remote_branch_exists(repo, branch):
                raise RuntimeError(f"{repo.name}: branch already exists: {branch}")
            bases.append(checked(h, repo, "rev-parse", "--verify", f"{args.base}^{{commit}}"))
        for repo, base in zip(repos, bases):
            checked(h, repo, "switch", "--no-track", "-c", branch, base)
            h.info(f"OK   {repo.name}: {branch} from {args.base} ({base})")
        if include_parent:
            h.write_branch_set(root, branch, {m.name: branch for m in modules})
        return 0
    except RuntimeError as exc:
        return h.fail(str(exc))


def read_lock(h, root, data=None):
    if data is None:
        data = json.loads((root / LOCK).read_text())
    workspace = h.load_workspace(root)
    if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(data.get("modules"), list):
        raise RuntimeError("Unsupported workspace.lock schema.")
    entries = data["modules"]
    if any(not isinstance(e, dict) or not all(isinstance(e.get(k), str) for k in ("name", "path", "url", "commit")) for e in entries):
        raise RuntimeError("Invalid lock module entry.")
    by_name = {e["name"]: e for e in entries}
    if len(by_name) != len(entries) or set(by_name) != {m.name for m in workspace.modules}:
        raise RuntimeError("Lock must contain every manifest module exactly once.")
    paths = [Path(m.path) for m in workspace.modules]
    if len(set(paths)) != len(paths) or any(a in b.parents for a in paths for b in paths if a != b):
        raise RuntimeError("Module paths must be distinct and non-overlapping.")
    for module in workspace.modules:
        entry = by_name[module.name]
        if entry["path"] != module.path or entry["url"] != module.url:
            raise RuntimeError(f"{module.name}: lock path/URL differs from workspace.ini.")
        h.validate_commit(entry["commit"])
        if module.commit and module.commit != entry["commit"]:
            raise RuntimeError(f"{module.name}: lock differs from manifest commit pin.")
        repo = root / module.path
        if repo.is_symlink() or not repo.resolve().is_relative_to(root.resolve()):
            raise RuntimeError(f"Unsafe module path: {module.path}")
    return entries


def lock_command(h, args):
    try:
        root = h.get_repo_root()
        if args.lock_action == "capture":
            entries = []
            for m in h.load_workspace(root).modules:
                repo = root / m.path
                if not args.from_main:
                    clean(h, repo)
                ref = "HEAD"
                if args.from_main:
                    checked(h, repo, "fetch", "origin", m.tag or "main")
                    ref = "FETCH_HEAD"
                entries.append(dict(name=m.name, path=m.path, url=m.url,
                                    commit=checked(h, repo, "rev-parse", f"{ref}^{{commit}}")))
            data = dict(schema=1, modules=entries)
            read_lock(h, root, data)
            temporary = root / (LOCK + ".tmp")
            temporary.write_text(json.dumps(data, indent=2) + "\n")
            temporary.replace(root / LOCK)
        else:
            entries = read_lock(h, root)
            if getattr(args, "modules", None):
                names = {m.name for m in h.select_modules(h.load_workspace(root), args.modules)}
                entries = [e for e in entries if e["name"] in names]
            # All existing clones are checked before any checkout takes place.
            for e in entries:
                repo = root / e["path"]
                if repo.exists():
                    clean(h, repo)
                    origin = checked(h, repo, "remote", "get-url", "origin")
                    if (h.url_to_https(origin) or origin).removesuffix(".git") != (h.url_to_https(e["url"]) or e["url"]).removesuffix(".git"):
                        raise RuntimeError(f"{e['name']}: origin differs from lock URL.")
                elif args.lock_action == "verify":
                    raise RuntimeError(f"Missing clone: {e['name']}")
            for e in entries:
                repo = root / e["path"]
                if args.lock_action == "checkout":
                    if not repo.exists():
                        checked(h, root, "clone", "--filter=blob:none", "--no-checkout", "--", e["url"], e["path"])
                    checked(h, repo, "fetch", "origin", e["commit"])
                    checked(h, repo, "checkout", "--detach", e["commit"])
                actual = checked(h, repo, "rev-parse", "HEAD")
                if actual != e["commit"]:
                    raise RuntimeError(f"{e['name']}: HEAD differs from lock; use lock checkout.")
                if args.merged:
                    module = h.load_workspace(root).module_by_selector()[e["name"]]
                    checked(h, repo, "fetch", "origin", module.tag or "main")
                    if module.tag:
                        expected = checked(h, repo, "rev-parse", "FETCH_HEAD^{commit}")
                        if e["commit"] != expected:
                            raise RuntimeError(f"{module.name}: SHA differs from pinned tag.")
                    else:
                        checked(h, repo, "merge-base", "--is-ancestor", e["commit"], "FETCH_HEAD")
        h.info(f"OK   lock {args.lock_action}: {len(entries)} modules")
        return 0
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as exc:
        return h.fail(str(exc))


def next_version(previous, bump):
    match = VERSION.fullmatch(previous)
    if not match:
        raise RuntimeError(f"Unsupported release version: {previous}")
    major, minor, patch = map(int, match.groups()[:3])
    rc = match[4]
    if bump == "rc":
        if rc is None:
            raise RuntimeError("rc requires a previous release candidate; use minor/major first.")
        return f"{major}.{minor}.{patch}-rc{int(rc) + 1}"
    if bump == "stable":
        if rc is None:
            raise RuntimeError("stable requires a previous release candidate.")
        return f"{major}.{minor}.{patch}"
    if rc is not None:
        raise RuntimeError("During prerelease use release:rc or release:stable.")
    return {"patch": f"{major}.{minor}.{patch+1}",
            "minor": f"{major}.{minor+1}.0", "major": f"{major+1}.0.0"}[bump]


def release_plan(h, root, bump, remote=False):
    namespace = 'refs/githelper/releases/' if remote else 'refs/tags/'
    tags = [ref[len(namespace):] for ref in checked(h, root, 'for-each-ref', '--format=%(refname)', namespace).splitlines()]
    versions = [t for t in tags if VERSION.fullmatch(t)]
    if not versions:
        raise RuntimeError("No numbered release tag found; bootstrap a baseline tag first.")
    def key(tag):
        m = VERSION.fullmatch(tag)
        return (*map(int, m.groups()[:3]), int(m[4]) if m[4] else float("inf"))
    previous = max(versions, key=key)
    checked(h, root, "merge-base", "--is-ancestor", namespace + previous, "HEAD")
    return dict(previous=previous, version=next_version(previous, bump), bump=bump)


def stamp(root, version, modules):
    """Apply the build version to active inherited POMs and npm metadata only."""
    from platform_versioning import set_platform_version
    set_platform_version(root, version)
    (root / "VERSION").write_text(version + "\n")


def version_command(h, args):
    from platform_versioning import read_version, set_platform_version, version_changes
    try:
        root = h.get_repo_root()
        version = args.version if args.version_action == "set" else read_version(root)
        if getattr(args, "check", False):
            changes = version_changes(root, version)
            if changes:
                raise RuntimeError("Version metadata differs from parent: " + ", ".join(str(p.relative_to(root)) for p in changes))
            h.info(f"OK   workspace package versions match {version}")
        else:
            changes = set_platform_version(root, version)
            h.info(f"OK   platform version {version}: updated {len(changes)} files (legacy excluded)")
        return 0
    except (RuntimeError, OSError, ValueError, ET.ParseError) as exc:
        return h.fail(str(exc))



def release_command(h, args):
    try:
        root = h.get_repo_root()
        if args.release_action == "stamp":
            if not VERSION.fullmatch(args.version):
                raise RuntimeError("Invalid release version.")
            stamp(root, args.version, read_lock(h, root))
        else:
            bump = args.bump
            if args.labels_json is not None:
                labels = json.loads(args.labels_json)
                selected = [label["name"][8:] for label in labels if label["name"].startswith("release:")]
                if len(selected) != 1 or selected[0] not in ("patch", "minor", "major", "rc", "stable"):
                    raise RuntimeError("Coordinator PR needs exactly one release:{patch,minor,major,rc,stable} label.")
                bump = selected[0]
            if not bump:
                raise RuntimeError("Use --bump or --labels-json.")
            h.info(json.dumps(release_plan(h, root, bump)))
        return 0
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as exc:
        return h.fail(str(exc))


def register_commands(parser, subparsers, h):
    from githelper_coordination import dispatch
    pr = subparsers.add_parser("pr", help="Push committed feature changes and create/update module and coordinator PRs (requires gh).")
    pr.set_defaults(func=lambda args: dispatch(h, "pr", args))
    versions = subparsers.add_parser("version", help="Synchronize active inherited Maven and npm versions.")
    commands = versions.add_subparsers(dest="version_action", required=True)
    sync = commands.add_parser("sync")
    sync.add_argument("--check", action="store_true", help="Check alignment without writing files.")
    sync.set_defaults(func=lambda args: version_command(h, args))
    set_version = commands.add_parser("set")
    set_version.add_argument("version")
    set_version.set_defaults(func=lambda args: version_command(h, args))
    feature = subparsers.add_parser("feature", help="Coordinated feature branches from main.")
    commands = feature.add_subparsers(dest="feature_action", required=True)
    start = commands.add_parser("start")
    start.add_argument("branch")
    start.add_argument("--modules", required=True)
    start.add_argument("--base", default="origin/main")
    start.set_defaults(func=lambda args: create_branches(h, args, True))
    add = commands.add_parser("add", help="Add modules to the current coordinated feature from origin/main.")
    add.add_argument("modules", help="Comma-separated module names.")
    add.set_defaults(func=lambda args: dispatch(h, "add", args))
    lock = subparsers.add_parser("lock", help="Capture, checkout or verify exact module commits.")
    commands = lock.add_subparsers(dest="lock_action", required=True)
    for action in ("capture", "checkout", "verify"):
        command = commands.add_parser(action)
        if action == "capture":
            command.add_argument("--from-main", action="store_true", help="Fetch main (or pinned tag), ignoring local worktrees.")
        command.add_argument("--merged", action="store_true", help="Require each SHA to belong to origin/main.")
        command.set_defaults(func=lambda args: lock_command(h, args))
    release = subparsers.add_parser("release")
    commands = release.add_subparsers(dest="release_action", required=True)
    prepare = commands.add_parser("prepare", help="Commit aligned versions and lock; repeat after module merges.")
    prepare.add_argument("--bump", required=True, choices=("patch", "minor", "major", "rc", "stable"))
    prepare.set_defaults(func=lambda args: dispatch(h, "prepare", args))
    plan = commands.add_parser("plan")
    plan.add_argument("--bump", choices=("patch", "minor", "major", "rc", "stable"))
    plan.add_argument("--labels-json")
    plan.set_defaults(func=lambda args: release_command(h, args))
    command = commands.add_parser("stamp")
    command.add_argument("version")
    command.set_defaults(func=lambda args: release_command(h, args))
