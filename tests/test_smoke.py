import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def test_readme_exists():
    assert (ROOT / "README.md").exists()


def test_pyproject_metadata():
    text = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    assert 'name = "zqm-hermes-skills"' in text
