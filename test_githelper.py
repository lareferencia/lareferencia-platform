import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
GITHELPER = ROOT / "githelper"


def load_githelper():
    loader = importlib.machinery.SourceFileLoader("githelper_under_test", str(GITHELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


githelper = load_githelper()


def run(cmd, cwd):
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def git(cmd, cwd):
    return run(["git", *cmd], cwd)


def init_repo(path):
    path.mkdir(parents=True, exist_ok=True)
    git(["init", "-b", "main"], path)
    git(["config", "user.email", "test@example.com"], path)
    git(["config", "user.name", "Test User"], path)


class WorkspaceParsingTests(unittest.TestCase):
    def test_workspace_defaults_and_profile_overlay(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "workspace.ini").write_text(
                textwrap.dedent(
                    """
                    [workspace]
                    default_branch = main

                    [module.mod-a]
                    url = https://example.test/mod-a

                    [module.mod-b]
                    url = https://example.test/mod-b
                    branch = develop

                    [profile.feature-x]
                    mod-a = feature-x
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )

            workspace = githelper.load_workspace(root)
            modules = {module.name: module for module in workspace.modules}

            self.assertEqual(workspace.default_branch, "main")
            self.assertEqual(modules["mod-a"].branch, "main")
            self.assertEqual(modules["mod-b"].branch, "develop")
            self.assertEqual(
                githelper.target_branch_for_module(workspace, "feature-x", modules["mod-a"]),
                "feature-x",
            )
            self.assertEqual(
                githelper.target_branch_for_module(workspace, "feature-x", modules["mod-b"]),
                "develop",
            )
            self.assertEqual(
                githelper.target_branch_for_module(workspace, "missing-profile", modules["mod-a"]),
                "main",
            )

    def test_select_modules_accepts_comma_lists(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "workspace.ini").write_text(
                textwrap.dedent(
                    """
                    [workspace]
                    default_branch = main

                    [module.mod-a]
                    url = https://example.test/mod-a

                    [module.mod-b]
                    url = https://example.test/mod-b
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )

            workspace = githelper.load_workspace(root)
            selected = githelper.select_modules(workspace, "mod-b,mod-a,mod-b")

            self.assertEqual([module.name for module in selected], ["mod-b", "mod-a"])


class MigrationSmokeTests(unittest.TestCase):
    def test_migrate_from_submodules_in_place(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "module-src"
            parent = root / "parent"

            init_repo(source)
            (source / "README.md").write_text("module\n", encoding="utf-8")
            git(["add", "README.md"], source)
            git(["commit", "-m", "initial module"], source)

            init_repo(parent)
            (parent / "workspace.ini").write_text(
                textwrap.dedent(
                    f"""
                    [workspace]
                    default_branch = main

                    [module.module]
                    url = {source}
                    branch = main
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )
            git(["add", "workspace.ini"], parent)
            git(["commit", "-m", "add workspace manifest"], parent)
            run(["git", "-c", "protocol.file.allow=always", "submodule", "add", str(source), "module"], parent)
            git(["commit", "-m", "add submodule"], parent)

            dry_run = run(
                [sys.executable, str(GITHELPER), "migrate", "from-submodules", "--in-place", "--dry-run"],
                parent,
            )
            self.assertIn("dry-run", dry_run.stdout)

            run([sys.executable, str(GITHELPER), "migrate", "from-submodules", "--in-place"], parent)

            ls_files = git(["ls-files", "-s"], parent).stdout
            self.assertNotIn("160000", ls_files)
            self.assertTrue((parent / "module" / ".git").is_dir())
            self.assertFalse((parent / ".gitmodules").exists())
            self.assertEqual(git(["-C", "module", "status", "--short"], parent).stdout.strip(), "")

            config_result = subprocess.run(
                ["git", "config", "--get-regexp", r"^submodule\."],
                cwd=str(parent),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(config_result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
