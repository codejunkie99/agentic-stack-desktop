"""One scoped read interface for reviewed claims, imported notes and conversations."""
from __future__ import annotations

import hashlib
import json
import re


class MemorySources:
    def __init__(self, graph, *, conversations=None, exclude_conversation='', topic=''):
        self.graph, self.conversations = graph, conversations
        self.exclude_conversation = exclude_conversation
        self.topic = topic

    @staticmethod
    def _claim_row(db, wid, row):
        identifier, body, kind, revision, evidence_ids = row
        origins = []
        for eid in json.loads(evidence_ids):
            evidence = db.execute('SELECT source_key,metadata FROM memory_evidence WHERE workspace_id=? AND id=?', (wid, eid)).fetchone()
            if evidence:
                origins.append({'path': evidence[0], 'line': 1, 'evidenceId': eid})
        return dict(id='claim:' + identifier, title=body.splitlines()[0][:160], body=body,
                    kind='memory', memoryKind=kind, status='accepted', review={'revision': revision},
                    digest=hashlib.sha256(body.encode()).hexdigest(), origins=origins)

    def _claims(self, wid, query, *, offset=0, limit=20, identifier=None):
        store = getattr(self.graph, 'store', None)
        if store is None:
            return [], 0
        # Validate workspace before opening any scoped claims.
        store.get('workspace', wid)
        with store.lock, store.connect() as db:
            if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='memory_claims'").fetchone():
                return [], 0
            where, values = "workspace_id=? AND status='accepted'", [wid]
            if identifier is not None:
                where += ' AND id=?'; values.append(identifier)
            elif query:
                terms = list(dict.fromkeys(re.findall(r'[\w-]{3,}', query.casefold())))[:18]
                if terms:
                    where += ' AND (' + ' OR '.join('instr(lower(body),?)>0' for _ in terms) + ')'
                    values.extend(terms)
            count = db.execute('SELECT count(*) FROM memory_claims WHERE ' + where, values).fetchone()[0]
            rows = db.execute('SELECT id,body,kind,revision,evidence_ids FROM memory_claims WHERE ' + where +
                              ' ORDER BY created_at,id LIMIT ? OFFSET ?', (*values, limit, offset)).fetchall()
            return [self._claim_row(db, wid, row) for row in rows], count

    def accepted_candidates(self, wid, query, *, limit=80):
        return self._claims(wid, query, limit=limit)[0]

    def _chats(self, wid, query):
        if self.conversations is None:
            return []
        from .context_packs import conversation_candidates
        return conversation_candidates(self.conversations, wid, query, self.exclude_conversation)

    def candidate_page(self, wid, query, *, offset=0, limit=20):
        # Three concatenated scoped streams; offsets count across stream boundaries.
        claims, claim_count = self._claims(wid, query, offset=offset, limit=limit)
        rows = list(claims)
        chats = self._chats(wid, query)
        chat_offset = max(0, offset - claim_count)
        if len(rows) < limit and offset + len(rows) >= claim_count:
            rows.extend(chats[chat_offset:chat_offset + limit - len(rows)])
        extras = claim_count + len(chats)
        more = offset + len(rows) < extras
        if len(rows) < limit and offset + len(rows) >= extras:
            page = self.graph.candidate_page(wid, query, offset=max(0, offset - extras), limit=limit - len(rows))
            rows.extend(page['rows']); more = page['hasMore']
        elif not more:
            # The page ended exactly on a stream boundary; inspect existence only.
            more = bool(self.graph.candidate_page(wid, query, offset=max(0, offset + len(rows) - extras), limit=1)['rows'])
        return {'rows': rows, 'nextOffset': offset + len(rows), 'hasMore': more}

    @staticmethod
    def _source_row(row):
        return dict(id='source:' + row['id'], title=row['name'], body=row['text'], kind='source',
                    status='reference', source=row.get('origin') or 'workspace source:' + row['id'],
                    digest=hashlib.sha256(row['text'].encode()).hexdigest(),
                    review={'approved': row['approved'], 'reviewedAt': row.get('reviewedAt')},
                    origins=[{'path': row.get('origin') or 'workspace source:' + row['id'], 'line': 1}])

    def context_candidates(self, wid, query, *, streams, limit=16):
        """Represent each scoped stream before one bounded Jev batch.

        Lexical discovery is host work; broad imported rows give the model a
        chance to find a match outside the lexical shortlist. No source is
        claimed inspected beyond its supplied exact prefix.
        """
        groups = []
        store = getattr(self.graph, 'store', None)
        if store is not None:
            store.get('workspace', wid)
        if self.topic and 'memory' in streams:
            ranked = self.graph.query(dict(workspaceId=wid, query=query[:300], topic=self.topic))
            broad = self.graph.query(dict(workspaceId=wid, query='', topic=self.topic))
            groups.append(list({r['id']: r for r in ranked['notes'] + broad['notes']
                                if r.get('status', 'reference') in {'reference', 'accepted'}}.values()))
        elif 'memory' in streams:
            claims = self.accepted_candidates(wid, query, limit=limit + 1) + self.accepted_candidates(wid, '', limit=limit + 1)
            groups.append(list({r['id']: r for r in claims}.values()))
            candidates = self.graph.candidates(wid, query, limit=limit + 1)
            if hasattr(self.graph, 'candidate_page'):
                candidates += self.graph.candidate_page(wid, '', limit=limit + 1)['rows']
            groups.append(list({r['id']: r for r in candidates}.values()))
        if 'conversations' in streams:
            groups.append(self._chats(wid, query))
        if store is not None and ('memory' in streams or 'sources' in streams):
            groups.append([self._source_row(r) for r in store.all('source')
                           if r.get('workspaceId') == wid and r.get('approved') is True])
        rows = [group[index] for index in range(max((len(group) for group in groups), default=0))
                for group in groups if index < len(group)]
        rows = list({r['id']: r for r in rows}.values())
        if self.topic:
            rows = [r for r in rows if self.topic in r.get('topics', [])]
        return rows[:limit], len(rows) > limit

    def note(self, wid, identifier):
        if identifier.startswith('source:'):
            row = self.graph.store.get('source', identifier.removeprefix('source:'))
            if row.get('workspaceId') != wid or row.get('approved') is not True:
                raise ValueError('Reviewed source unavailable in this workspace.')
            return self._source_row(row)
        if identifier.startswith('claim:'):
            rows, _ = self._claims(wid, '', identifier=identifier.removeprefix('claim:'))
            if not rows:
                raise ValueError('Accepted memory claim unavailable in this workspace.')
            return rows[0]
        if identifier.startswith(('native:', 'live:')) and self.conversations is not None:
            from .context_packs import conversation_note
            if identifier == 'native:' + self.exclude_conversation:
                raise ValueError('Current conversation is excluded.')
            return conversation_note(self.conversations, wid, identifier)
        return self.graph.note(wid, identifier)
