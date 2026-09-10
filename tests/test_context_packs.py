import hashlib
import json
import threading
from pathlib import Path
from unittest.mock import patch

import pytest

from harness_manager.context_mcp import MCPServer, search_memory
from harness_manager.loops.process import ProcessResult
from harness_manager.workspaces.context_packs import ContextPacks, options, rank_candidates
from harness_manager.workspaces.knowledge import KnowledgeGraph
from harness_manager.workspaces.service import WorkspaceService


class Graph:
    def __init__(self):
        self.rows = [dict(id=str(i), title=f'Decision {i}', body=('exact source Ω ' * 500),
                         digest=str(i), origins=[dict(path=f'/source/{i}', line=1)], status='reference', review=None)
                     for i in range(6)]

    def candidates(self, wid, prompt, limit=80):
        return [r for r in self.rows if r['status'] in {'reference', 'accepted'}][:limit]

    def note(self, wid, identifier):
        return next(r for r in self.rows if r['id'] == identifier)


def test_bounded_exact_excerpts_pins_exclusions_and_cache_invalidation():
    graph, packs = Graph(), ContextPacks()
    config = dict(mode='local', tokenBudget=1000, pinnedIds=['3'], excludeIds=['0'])
    first = packs.prepare(graph, 'w', 'Decision', config)
    assert first['refs'][0]['id'] == '3'
    assert len(first['refs']) >= 3
    assert all(r['id'] != '0' and r['truncated'] for r in first['refs'])
    assert first['estimatedTokens'] <= 1000 and 'not authority or permission' in first['text']
    for ref in first['refs']:
        assert graph.note('w', ref['id'])['body'].startswith(ref['excerpt'])
    assert packs.prepare(graph, 'w', 'Decision', config)['cacheHit']
    graph.rows[3].update(status='superseded', review={'revision': 1})
    second = packs.prepare(graph, 'w', 'Decision', config)
    assert not second['cacheHit'] and all(r['id'] != '3' for r in second['refs'])
    graph.rows[1]['body'] = 'Changed original content'
    graph.rows[1]['digest'] = 'new-digest'
    assert not packs.prepare(graph, 'w', 'Decision', config)['cacheHit']


@pytest.mark.parametrize('ids', [['invented'], ['1', '1'], [True], '1'])
def test_ranker_rejects_forged_or_duplicate_ids_and_falls_back(ids, monkeypatch):
    graph = Graph()
    monkeypatch.setattr('harness_manager.workspaces.context_packs.executable', lambda _: '/agent')
    result = ProcessResult('completed', 0, json.dumps({'result': json.dumps({'ids': ids})}), '', 0, .01)
    with patch('harness_manager.workspaces.context_packs.run_profile', return_value=result):
        pack = ContextPacks().prepare(graph, 'w', 'Decision', dict(mode='agent', agent='claude-code'))
    assert pack['status'] == 'fallback' and pack['refs']
    assert 'invalid evidence IDs' in pack['warning']
    assert all(r['id'] in {n['id'] for n in graph.rows} for r in pack['refs'])


def test_ranker_is_bounded_isolated_and_cancellable(tmp_path, monkeypatch):
    monkeypatch.setenv('CODEX_HOME', str(tmp_path))
    (tmp_path/'config.toml').write_text('[mcp_servers.agentic-stack]\ncommand="unused"\n')
    monkeypatch.setattr('harness_manager.workspaces.context_packs.executable', lambda _: '/agent')
    cancelled = threading.Event()
    def execute(profile, values, cwd, limit, event):
        from harness_manager.loops.process import expand_command
        command = expand_command(profile['command'], values)
        assert 'mcp_servers.agentic-stack.enabled=false' in command
        assert '--ignore-user-config' not in command and '--ignore-rules' not in command
        assert '--sandbox' in command and 'read-only' in command
        assert profile['timeout_seconds'] == 2 and limit == 16000
        assert cwd != tmp_path and 'ids' in values['prompt']
        event.set()
        return ProcessResult('cancelled', None, '', '', 0, .01)
    with patch('harness_manager.workspaces.context_packs.run_profile', side_effect=execute):
        with pytest.raises(InterruptedError):
            rank_candidates(Graph().rows, 'Decision', options(dict(mode='agent', timeoutSeconds=2)), cancelled)
    with pytest.raises(InterruptedError):
        ContextPacks().prepare(Graph(), 'w', 'Decision', dict(mode='local'), cancelled)


def test_ranker_preserves_safe_provider_failure_category(monkeypatch):
    monkeypatch.setattr('harness_manager.workspaces.context_packs.executable', lambda _: '/agent')
    result = ProcessResult('failed', 1, 'local_router_error: private diagnostic', '', 0, .01)
    with patch('harness_manager.workspaces.context_packs.run_profile', return_value=result):
        pack = ContextPacks().prepare(Graph(), 'w', 'Decision', dict(mode='agent', agent='claude-code'))
    assert 'router rejected' in pack['warning'] and 'private diagnostic' not in pack['warning']
    assert pack['status'] == 'fallback' and pack['refs']


@pytest.mark.parametrize('agent', ['codex', 'claude-code'])
def test_successful_ranker_can_only_reorder_exact_evidence(agent, tmp_path, monkeypatch):
    monkeypatch.setenv('CODEX_HOME', str(tmp_path))
    monkeypatch.setattr('harness_manager.workspaces.context_packs.executable', lambda _: '/agent')
    selection = json.dumps({'ids': ['3', '1']})
    output = (json.dumps([{'type': 'system'}, {'type': 'result', 'result': selection, 'is_error': False}])
              if agent == 'claude-code' else json.dumps({'type': 'item.completed',
                  'item': {'type': 'agent_message', 'text': selection}}))
    with patch('harness_manager.workspaces.context_packs.run_profile', return_value=ProcessResult('completed', 0, output, '', 0, .01)):
        pack = ContextPacks().prepare(Graph(), 'w', 'Decision', dict(mode='agent', agent=agent))
    assert pack['status'] == 'ready' and pack['retrievalAgent'] == agent
    assert [r['id'] for r in pack['refs']] == ['3', '1']
    assert all(Graph().note('w', ref['id'])['body'].startswith(ref['excerpt']) for ref in pack['refs'])


@pytest.mark.parametrize('config', [{'tokenBudget': True}, {'tokenBudget': 255}, {'mode': 'magic'},
                                   {'pinnedIds': 'id'}, {'timeoutSeconds': 100}, {'unknown': 1}])
def test_invalid_context_options(config):
    with pytest.raises(ValueError):
        options(config)


def test_mcp_prepares_same_memory_with_read_only_database(tmp_path, monkeypatch):
    service = WorkspaceService(tmp_path/'data')
    project = tmp_path/'project'; project.mkdir()
    workspace = service.open_project({'path': str(project)})
    home = tmp_path/'home'; home.mkdir()
    service.knowledge = KnowledgeGraph(service.store, service.stack, home=home)
    source = home/'.codex/memories/MEMORY.md'; source.parent.mkdir(parents=True)
    source.write_text('# Engine choice\nUse SQLite for local project storage.')
    preview = service.knowledge.preview(dict(workspaceId=workspace['id'], providers=['codex']))
    service.knowledge.import_preview(dict(workspaceId=workspace['id'], previewId=preview['id'], sourceIds=[f['id'] for f in preview['files']]))
    monkeypatch.setenv('AGENTIC_WORKSPACES_DATA', str(service.store.root))
    before = {p: p.read_bytes() for p in [source, service.store.path]}
    try:
        desktop = ContextPacks().prepare(service.knowledge, workspace['id'], 'SQLite storage', dict(mode='local'))
        server = MCPServer(home)
        shared = server.prepare_context(dict(workspaceId=workspace['id'], prompt='SQLite storage'))
        assert shared['refs'] == desktop['refs']
        assert search_memory('SQLite', home=home)[0]['status'] == 'reference'
        assert all(p.read_bytes() == raw for p, raw in before.items())
        note = desktop['refs'][0]
        service.knowledge.review_note(dict(workspaceId=workspace['id'], noteId=note['id'], status='retracted', reason='No longer valid'))
        assert server.prepare_context(dict(workspaceId=workspace['id'], prompt='SQLite storage'))['refs'] == []
        assert search_memory('SQLite', home=home) == []
    finally:
        service.close()


def test_automatic_conversations_are_scoped_and_exact(tmp_path, monkeypatch):
    service = WorkspaceService(tmp_path/'data')
    project = tmp_path/'project'; project.mkdir()
    workspace = service.open_project({'path': str(project)})
    other = service.create_workspace(dict(name='Other', goal='Other project'))
    for ws, phrase in [(workspace, 'Quartz release uses SQLite.'), (other, 'Quartz private other project.')]:
        chat = service.store.create('conversation', dict(workspaceId=ws['id'], agent='codex', title='Quartz release', mode='read-only'))
        service.store.create('run', dict(workspaceId=ws['id'], conversationId=chat['id'], task='Quartz?', output=phrase,
                                        status='completed', reviewed=True, provider='local'))
    monkeypatch.setattr(service.conversation_refs, '_live', lambda: [])
    try:
        pack = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Quartz release'))
        assert any(r['kind'] == 'conversation' for r in pack['refs'])
        assert 'Quartz release uses SQLite.' in pack['text'] and 'private other' not in pack['text']
        identifier = next(r['id'] for r in pack['refs'] if r['kind'] == 'conversation')
        config = dict(mode='local', pinnedIds=[identifier])
        pinned = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Unrelated', contextOptions=config))
        assert pinned['refs'][0]['id'] == identifier and pinned['refs'][0]['reason'] == 'Pinned by you'
        run = next(r for r in service.store.all('run') if r['workspaceId'] == workspace['id'])
        service.store.update('run', run['id'], output='Quartz now uses a revised release process.')
        changed = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Unrelated', contextOptions=config))
        assert not changed['cacheHit'] and changed['refs'][0]['digest'] != pinned['refs'][0]['digest']
        foreign = next(c for c in service.store.all('conversation') if c['workspaceId'] == other['id'])
        rejected = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Unrelated',
            contextOptions=dict(mode='local', pinnedIds=['native:' + foreign['id']])))
        assert rejected['refs'] == [] and rejected['warning']
    finally:
        service.close()


def test_pinned_live_chat_refreshes_only_its_source(tmp_path):
    service = WorkspaceService(tmp_path/'data')
    project = tmp_path/'project'; project.mkdir()
    workspace = service.open_project({'path': str(project)})
    home = tmp_path/'home'; home.mkdir()
    service.knowledge = KnowledgeGraph(service.store, service.stack, home=home)
    source = home/'.codex/sessions/source.jsonl'; source.parent.mkdir(parents=True)
    def write(body, cwd=project):
        source.write_text('\n'.join(json.dumps(row) for row in [
            {'type': 'session_meta', 'payload': {'cwd': str(cwd)}},
            {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
                'content': [{'type': 'input_text', 'text': body}]}}]))
    try:
        write('Mercury launch original evidence.')
        original = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Mercury'))
        identifier = original['refs'][0]['id']
        assert identifier.startswith('live:')
        config = dict(mode='local', pinnedIds=[identifier])
        write('Mercury launch revised evidence.')
        changed = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Unrelated', contextOptions=config))
        assert 'revised evidence' in changed['text'] and 'original evidence' not in changed['text']
        write('Foreign secret project evidence.', tmp_path/'other')
        rejected = service.dispatch('context.prepare', dict(workspaceId=workspace['id'], prompt='Mercury', contextOptions=config))
        assert rejected['refs'] == [] and rejected['warning']
    finally:
        service.close()
