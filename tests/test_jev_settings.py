import json
import os
import pytest
from harness_manager.workspaces.jev_settings import JevSettings, ConfiguredJevProvider


def test_explicit_consent_required_and_public_status_has_no_secret(tmp_path):
    settings = JevSettings(tmp_path)
    with pytest.raises(ValueError):
        settings.configure(token='synthetic-token', enabled=True, consent=False)
    assert not settings.path.exists()
    status = settings.configure(token='synthetic-token', enabled=True, consent=True)
    assert status['enabled'] and status['configured']
    assert 'synthetic-token' not in json.dumps(status)
    assert os.stat(settings.path).st_mode & 0o777 == 0o600


def test_instances_reload_and_disconnect_without_touching_evidence(tmp_path):
    settings = JevSettings(tmp_path)
    first = ConfiguredJevProvider(settings)
    second = ConfiguredJevProvider(JevSettings(tmp_path))
    assert not first.available and not second.available
    settings.configure(token='synthetic-token', enabled=True, consent=True)
    assert first.available and second.available
    evidence = tmp_path/'evidence.txt'; evidence.write_text('Preserve this')
    settings.disconnect()
    assert not first.available and not second.available
    assert evidence.read_text() == 'Preserve this'


def test_insecure_symlink_and_malformed_config_fail_closed(tmp_path):
    settings = JevSettings(tmp_path)
    settings.configure(token='synthetic-token', enabled=True, consent=True)
    settings.path.chmod(0o644)
    assert not ConfiguredJevProvider(settings).available
    settings.path.unlink()
    target = tmp_path/'unrelated'; target.write_text('{}')
    settings.path.symlink_to(target)
    assert settings.read() == {}
    settings.disconnect()
    assert target.read_text() == '{}'


def test_desktop_setup_is_seen_by_existing_read_only_mcp(tmp_path, monkeypatch):
    from harness_manager.workspaces.service import WorkspaceService
    from harness_manager.context_mcp import MCPServer
    root = tmp_path/'data'
    monkeypatch.setenv('AGENTIC_WORKSPACES_DATA', str(root))
    service = WorkspaceService(root)
    mcp = MCPServer(tmp_path/'home')
    assert not mcp.context_packs.jev_provider.available
    status = service.dispatch('memory.provider.configure', dict(token='synthetic-token', enabled=True, consent=True))
    assert status['configured'] and 'token' not in status
    assert service.jev_memory.provider.available
    assert mcp.context_packs.jev_provider.available
    before = service.jev_settings.path.read_bytes()
    assert service.dispatch('memory.provider.status', {}) == status
    assert service.jev_settings.path.read_bytes() == before
    service.dispatch('memory.provider.disconnect', {})
    assert not mcp.context_packs.jev_provider.available
    service.close()
