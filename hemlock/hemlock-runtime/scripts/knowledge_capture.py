#!/usr/bin/env python3
# =============================================================================
# Hemlock — Global Knowledge Capture Engine (T15)
#
# The runtime-root, GLOBAL, APPEND-ONLY knowledge store shared by every agent.
# Any link or document an agent receives (via the gateway on ANY platform:
# Telegram, Signal, a pasted llm.txt, a URL, a websocket-delivered resource,
# an attached file) is captured here — never overwritten, never deleted — and
# recorded in a link database classified by USE / FUNCTION / SCOPE.
#
# This is a pure-stdlib argparse CLI on purpose: it ingests arbitrary, possibly
# hostile inbound text, so every value flows through argv/stdin — there is NO
# string interpolation into a shell or a second interpreter (the injection /
# newline-corruption class of bug that the old docs-indexer heredocs had).
#
# Offline-safe: capturing a URL records + classifies it WITHOUT fetching. A
# network fetch happens only with an explicit --fetch flag (no surprise egress).
#
# Store layout ($HEMLOCK_KNOWLEDGE_DIR, default $RUNTIME_ROOT/knowledge):
#   inbox/            APPEND-ONLY captured docs (timestamped, immutable names)
#   links.json        classified link database (use / function / scope)
#   index.json        derived keyword index (rebuildable cache — safe to delete)
#   config.json       engine configuration
#   CAPTURE-LOG.md    append-only human-readable ledger of every capture
#
# Commands:
#   url <URL> [--title T] [--use U] [--function F] [--scope S]
#             [--tag T]... [--source S] [--agent ID] [--fetch]
#   file <PATH> [--title T] [classification flags] [--source S] [--agent ID]
#   text  [--title T] [flags]         (content on stdin)  — e.g. a pasted llm.txt
#   message [--agent ID] [--source S] (message text on stdin or --text)
#                                     — the GATEWAY HOOK: auto-captures every
#                                       URL found in an inbound message
#   index <PATH>                      index one file into index.json (watcher use)
#   search <QUERY...>                 keyword search the store
#   list [--links|--docs]             list captured links / docs
#   status                            show store status
#   rebuild                           rebuild index.json from inbox/ + links.json
# =============================================================================
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

SCHEMA_VERSION = "2.0.0"

# URLs inside free text; trailing punctuation is trimmed after the match.
_URL_RE = re.compile(r'(?i)\bhttps?://[^\s<>"\'\)\]}]+')
_TRIM = '.,;:!?\'"'


# ── paths / io ───────────────────────────────────────────────────────────────
def resolve_knowledge_dir(explicit: str | None) -> Path:
    """Canonical GLOBAL store: --knowledge-dir > $HEMLOCK_KNOWLEDGE_DIR >
    $RUNTIME_ROOT/knowledge > /data/knowledge (docker) > ./knowledge."""
    for cand in (explicit, os.environ.get("HEMLOCK_KNOWLEDGE_DIR")):
        if cand:
            return Path(cand).expanduser()
    root = os.environ.get("RUNTIME_ROOT")
    if root:
        return Path(root) / "knowledge"
    if Path("/data").is_dir():
        return Path("/data/knowledge")
    return Path.cwd() / "knowledge"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def ts_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")


def load_json(path: Path, default):
    try:
        with path.open("r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def save_json_atomic(path: Path, data) -> None:
    """Atomic write: temp in the same dir + os.replace (crash-safe)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def slugify(text: str, maxlen: int = 48) -> str:
    s = re.sub(r"[^a-zA-Z0-9._-]+", "-", (text or "").strip()).strip("-.")
    return (s[:maxlen] or "item").lower()


class Store:
    def __init__(self, root: Path):
        self.root = root
        self.inbox = root / "inbox"
        self.links_file = root / "links.json"
        self.index_file = root / "index.json"
        self.config_file = root / "config.json"
        self.log_file = root / "CAPTURE-LOG.md"

    def ensure(self) -> None:
        self.inbox.mkdir(parents=True, exist_ok=True)
        (self.root / ".gitkeep").touch(exist_ok=True)
        if not self.config_file.exists():
            save_json_atomic(self.config_file, {
                "version": SCHEMA_VERSION,
                "created_at": now_iso(),
                "append_only": True,
                "note": "inbox/ and links.json are append-only. index.json is a "
                        "rebuildable cache. Never delete captured knowledge.",
            })
        if not self.links_file.exists():
            save_json_atomic(self.links_file, _empty_links())
        if not self.log_file.exists():
            self.log_file.write_text(
                "# Hemlock Global Knowledge — Capture Log (append-only)\n\n",
                encoding="utf-8",
            )

    def log(self, line: str) -> None:
        try:
            with self.log_file.open("a", encoding="utf-8") as fh:
                fh.write(f"- {now_iso()}  {line}\n")
        except OSError:
            pass

    def unique_inbox_path(self, name: str) -> Path:
        """Append-only: never overwrite an existing inbox file."""
        p = self.inbox / name
        if not p.exists():
            return p
        stem, suffix = p.stem, p.suffix
        i = 1
        while True:
            alt = self.inbox / f"{stem}-{i}{suffix}"
            if not alt.exists():
                return alt
            i += 1


def _empty_links():
    return {
        "version": SCHEMA_VERSION,
        "updated": None,
        "links": [],
        "by_use": {},
        "by_function": {},
        "by_scope": {},
    }


# ── classification ───────────────────────────────────────────────────────────
def classify_url(url: str) -> dict:
    """Best-effort classification by use / function / scope from the URL alone.
    Deterministic, offline, heuristic — a starting point the agent can refine."""
    parsed = urlparse(url)
    host = (parsed.netloc or "").lower()
    path = (parsed.path or "").lower()
    low = url.lower()
    tags: list[str] = []

    use, function = "reference", "webpage"

    if re.search(r"/llms?(-full)?\.txt$", path) or low.endswith("llm.txt"):
        use, function = "llm-context", "context-file"
        tags.append("llm.txt")
    elif host.startswith("api.") or "/api/" in path or path.endswith((".api",)):
        use, function = "api", "api-endpoint"
    elif "github.com" in host or "gitlab.com" in host or "bitbucket.org" in host:
        use, function = "code", "repository"
        tags.append("vcs")
    elif ("docs." in host or "readthedocs" in host or "/docs" in path
          or "/wiki" in path or "developer." in host):
        use, function = "reference", "documentation"
    elif path.endswith(".pdf"):
        use, function = "document", "pdf"
    elif path.endswith((".json", ".yaml", ".yml", ".csv")):
        use, function = "data", "dataset"
    elif path.endswith((".md", ".txt", ".rst")):
        use, function = "document", "text"
    elif "youtube.com" in host or "youtu.be" in host or "vimeo.com" in host:
        use, function = "media", "video"

    if host:
        tags.append(host.replace("www.", ""))
    return {"use": use, "function": function, "domain": host, "tags": tags}


def _bump(counter: dict, key: str) -> None:
    counter[key] = counter.get(key, 0) + 1


# ── capture: links ───────────────────────────────────────────────────────────
def add_link(store: Store, url: str, *, title=None, use=None, function=None,
             scope="global", tags=None, source="manual", agent=None,
             content_file=None) -> tuple[dict, bool]:
    """Append-only accumulate. A re-sighting of a known URL bumps seen_count /
    last_seen (never a delete); classification defaults fill only blank fields."""
    url = url.strip()
    data = load_json(store.links_file, _empty_links())
    data.setdefault("links", [])
    auto = classify_url(url)
    link_id = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]

    existing = next((l for l in data["links"] if l.get("id") == link_id), None)
    is_new = existing is None
    if existing is None:
        existing = {
            "id": link_id,
            "url": url,
            "title": title or url,
            "use": use or auto["use"],
            "function": function or auto["function"],
            "scope": scope or "global",
            "domain": auto["domain"],
            "tags": sorted(set((tags or []) + auto["tags"])),
            "source": source,
            "received_by": [agent] if agent else [],
            "content_file": content_file,
            "added_at": now_iso(),
            "last_seen": now_iso(),
            "seen_count": 1,
        }
        data["links"].append(existing)
    else:
        existing["last_seen"] = now_iso()
        existing["seen_count"] = existing.get("seen_count", 1) + 1
        if title and (not existing.get("title") or existing["title"] == existing["url"]):
            existing["title"] = title
        if use:
            existing["use"] = use
        if function:
            existing["function"] = function
        if scope and scope != "global":
            existing["scope"] = scope
        if content_file and not existing.get("content_file"):
            existing["content_file"] = content_file
        if agent and agent not in existing.setdefault("received_by", []):
            existing["received_by"].append(agent)
        if tags:
            existing["tags"] = sorted(set(existing.get("tags", []) + list(tags)))

    # Rebuild facet counters from scratch (cheap, always consistent).
    data["by_use"], data["by_function"], data["by_scope"] = {}, {}, {}
    for l in data["links"]:
        _bump(data["by_use"], l.get("use", "reference"))
        _bump(data["by_function"], l.get("function", "webpage"))
        _bump(data["by_scope"], l.get("scope", "global"))
    data["updated"] = now_iso()
    save_json_atomic(store.links_file, data)

    store.log(f"LINK [{'new' if is_new else 'seen'}] {existing['use']}/"
              f"{existing['function']} scope={existing['scope']} "
              f"src={source}{' agent='+agent if agent else ''}  {url}")
    return existing, is_new


def maybe_fetch(url: str, timeout: float = 15.0) -> str | None:
    """Opt-in only. Returns fetched text or None (fail-soft, size-capped)."""
    try:
        import urllib.request
        req = urllib.request.Request(url, headers={"User-Agent": "Hemlock-Knowledge/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            return resp.read(5_000_000).decode("utf-8", errors="replace")
    except Exception:
        return None


# ── capture: files / text ────────────────────────────────────────────────────
def capture_bytes(store: Store, content: bytes, *, ext: str, title: str,
                  source: str, agent=None, origin_url=None) -> Path:
    name = f"{ts_stamp()}__{slugify(title)}{ext}"
    dest = store.unique_inbox_path(name)
    with dest.open("wb") as fh:
        fh.write(content)
    meta = {
        "captured_at": now_iso(), "title": title, "source": source,
        "agent": agent, "origin_url": origin_url, "bytes": len(content),
    }
    save_json_atomic(dest.with_suffix(dest.suffix + ".meta.json"), meta)
    store.log(f"DOC  {dest.name}  ({len(content)} bytes) src={source}"
              f"{' agent='+agent if agent else ''}"
              f"{' url='+origin_url if origin_url else ''}")
    return dest


def index_file(store: Store, path: Path) -> int:
    """Keyword-index one inbox file into index.json. Returns keyword count."""
    try:
        content = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return 0
    if len(content) < 1:
        return 0
    index = load_json(store.index_file, {
        "version": SCHEMA_VERSION, "last_indexed": None,
        "document_count": 0, "documents": {}, "keywords": {},
    })
    doc_id = hashlib.md5(str(path.name).encode()).hexdigest()
    words = set(re.findall(r"[a-zA-ZÀ-￿0-9]{4,}", content.lower()))
    index["documents"][doc_id] = {
        "id": doc_id,
        "name": path.name,
        "size": len(content),
        "content_hash": hashlib.md5(content.encode("utf-8", "replace")).hexdigest(),
        "keywords": sorted(words),
        "preview": content[:500],
        "indexed_at": now_iso(),
    }
    for kw in words:
        index["keywords"].setdefault(kw, [])
        if doc_id not in index["keywords"][kw]:
            index["keywords"][kw].append(doc_id)
    index["document_count"] = len(index["documents"])
    index["last_indexed"] = now_iso()
    save_json_atomic(store.index_file, index)
    return len(words)


# ── commands ─────────────────────────────────────────────────────────────────
def cmd_url(store: Store, a) -> int:
    content_file = None
    if a.fetch:
        text = maybe_fetch(a.url)
        if text is not None:
            dest = capture_bytes(store, text.encode("utf-8"), ext=".txt",
                                 title=a.title or a.url, source=a.source,
                                 agent=a.agent, origin_url=a.url)
            index_file(store, dest)
            content_file = str(dest.relative_to(store.root))
    link, is_new = add_link(store, a.url, title=a.title, use=a.use,
                            function=a.function, scope=a.scope, tags=a.tag,
                            source=a.source, agent=a.agent, content_file=content_file)
    print(json.dumps({"ok": True, "new": is_new, "link": link}, indent=2))
    return 0


def cmd_file(store: Store, a) -> int:
    src = Path(a.path)
    if not src.is_file():
        print(json.dumps({"ok": False, "error": f"not a file: {a.path}"}))
        return 1
    content = src.read_bytes()[:20_000_000]
    dest = capture_bytes(store, content, ext=src.suffix or ".bin",
                         title=a.title or src.name, source=a.source, agent=a.agent)
    index_file(store, dest)
    rel = str(dest.relative_to(store.root))
    if a.use or a.function or a.scope != "global" or a.tag:
        add_link(store, f"file://{rel}", title=a.title or src.name, use=a.use,
                 function=a.function or "document", scope=a.scope, tags=a.tag,
                 source=a.source, agent=a.agent, content_file=rel)
    print(json.dumps({"ok": True, "stored": rel}, indent=2))
    return 0


def cmd_text(store: Store, a) -> int:
    content = (a.text if a.text is not None else sys.stdin.read())
    if not content.strip():
        print(json.dumps({"ok": False, "error": "empty text"}))
        return 1
    dest = capture_bytes(store, content.encode("utf-8"), ext=".md",
                         title=a.title or "note", source=a.source, agent=a.agent)
    index_file(store, dest)
    print(json.dumps({"ok": True, "stored": str(dest.relative_to(store.root))}, indent=2))
    return 0


def cmd_message(store: Store, a) -> int:
    """GATEWAY HOOK: scan an inbound message, auto-capture every URL found.
    Fail-soft and side-effect-only — it never alters the agent's reply."""
    text = a.text if a.text is not None else sys.stdin.read()
    captured = []
    for m in _URL_RE.finditer(text or ""):
        url = m.group(0).rstrip(_TRIM)
        # balance a trailing ')' only if unmatched
        if url.endswith(")") and url.count("(") < url.count(")"):
            url = url[:-1]
        link, is_new = add_link(store, url, source=a.source, agent=a.agent)
        captured.append({"url": url, "new": is_new, "use": link["use"]})
    print(json.dumps({"ok": True, "captured": len(captured), "links": captured}, indent=2))
    return 0


def cmd_index(store: Store, a) -> int:
    n = index_file(store, Path(a.path))
    print(json.dumps({"ok": True, "file": a.path, "keywords": n}))
    return 0


def cmd_search(store: Store, a) -> int:
    query = " ".join(a.query)
    qwords = {w.lower() for w in re.findall(r"[a-zA-Z0-9]{3,}", query)}
    results = []
    index = load_json(store.index_file, {"documents": {}})
    for doc in index.get("documents", {}).values():
        hits = qwords & set(doc.get("keywords", []))
        if hits:
            results.append((len(hits), "doc", doc.get("name"), doc.get("preview", "")[:160], hits))
    links = load_json(store.links_file, _empty_links())
    for l in links.get("links", []):
        hay = f"{l.get('title','')} {l.get('url','')} {' '.join(l.get('tags',[]))}".lower()
        hits = {w for w in qwords if w in hay}
        if hits:
            results.append((len(hits), f"link:{l.get('use')}", l.get("url"), l.get("title", ""), hits))
    results.sort(key=lambda x: x[0], reverse=True)
    if not results:
        print(f"No results for: {query}")
        return 0
    for score, kind, ref, preview, hits in results[:25]:
        print(f"[{score}] ({kind}) {ref}\n    {preview}\n    ~ {', '.join(sorted(hits))}")
    print(f"\n{len(results)} result(s).")
    return 0


def cmd_list(store: Store, a) -> int:
    if not a.docs:
        links = load_json(store.links_file, _empty_links())
        print(f"Links ({len(links.get('links', []))}):")
        for l in links.get("links", []):
            print(f"  [{l.get('use')}/{l.get('function')}] scope={l.get('scope')} "
                  f"seen={l.get('seen_count')}  {l.get('url')}")
    if not a.links:
        docs = sorted(p.name for p in store.inbox.glob("*") if p.is_file()
                      and not p.name.endswith(".meta.json"))
        print(f"\nDocs ({len(docs)}):")
        for name in docs:
            print(f"  {name}")
    return 0


def cmd_status(store: Store, a) -> int:
    links = load_json(store.links_file, _empty_links())
    index = load_json(store.index_file, {"document_count": 0, "keywords": {}})
    docs = [p for p in store.inbox.glob("*") if p.is_file() and not p.name.endswith(".meta.json")]
    print(json.dumps({
        "knowledge_dir": str(store.root),
        "append_only": True,
        "links_total": len(links.get("links", [])),
        "by_use": links.get("by_use", {}),
        "by_function": links.get("by_function", {}),
        "by_scope": links.get("by_scope", {}),
        "inbox_docs": len(docs),
        "indexed_docs": index.get("document_count", 0),
        "keywords": len(index.get("keywords", {})),
        "updated": links.get("updated"),
    }, indent=2))
    return 0


def cmd_rebuild(store: Store, a) -> int:
    try:
        store.index_file.unlink()
    except OSError:
        pass
    n = 0
    for p in store.inbox.glob("*"):
        if p.is_file() and not p.name.endswith(".meta.json"):
            index_file(store, p)
            n += 1
    print(json.dumps({"ok": True, "reindexed": n}))
    return 0


# ── owner management (view / edit / archive / restore) ───────────────────────
# Append-only protects captured DOCUMENTS (inbox/ is immutable). Link
# classification metadata is explicitly the OWNER's to manage. "Removing" a link
# is a tombstone, not an erase: it moves to links.archive.json (auditable,
# restorable) so nothing is ever truly lost.
def _find_link(links: list, ref: str):
    ref = (ref or "").strip()
    for l in links:
        if l.get("id") == ref or l.get("url") == ref:
            return l
    hits = [l for l in links if l.get("id", "").startswith(ref)] if ref else []
    return hits[0] if len(hits) == 1 else None


def _archive_path(store: Store) -> Path:
    return store.root / "links.archive.json"


def cmd_show(store: Store, a) -> int:
    data = load_json(store.links_file, _empty_links())
    link = _find_link(data.get("links", []), a.ref)
    if not link:
        print(json.dumps({"ok": False, "error": f"no link matching '{a.ref}'"}))
        return 1
    print(json.dumps(link, indent=2, ensure_ascii=False))
    return 0


def cmd_edit(store: Store, a) -> int:
    data = load_json(store.links_file, _empty_links())
    link = _find_link(data.get("links", []), a.ref)
    if not link:
        print(json.dumps({"ok": False, "error": f"no link matching '{a.ref}'"}))
        return 1
    changed = []
    for field in ("title", "use", "function", "scope"):
        val = getattr(a, field)
        if val is not None:
            link[field] = val
            changed.append(field)
    tags = set(link.get("tags", []))
    for t in (a.add_tag or []):
        tags.add(t); changed.append(f"+tag:{t}")
    for t in (a.del_tag or []):
        tags.discard(t); changed.append(f"-tag:{t}")
    link["tags"] = sorted(tags)
    link["edited_at"] = now_iso()
    # Recompute facet counters.
    data["by_use"], data["by_function"], data["by_scope"] = {}, {}, {}
    for l in data["links"]:
        _bump(data["by_use"], l.get("use", "reference"))
        _bump(data["by_function"], l.get("function", "webpage"))
        _bump(data["by_scope"], l.get("scope", "global"))
    data["updated"] = now_iso()
    save_json_atomic(store.links_file, data)
    store.log(f"EDIT {link['id']} [{', '.join(changed) or 'no-op'}]  {link['url']}")
    print(json.dumps({"ok": True, "changed": changed, "link": link}, indent=2))
    return 0


def cmd_archive(store: Store, a) -> int:
    data = load_json(store.links_file, _empty_links())
    link = _find_link(data.get("links", []), a.ref)
    if not link:
        print(json.dumps({"ok": False, "error": f"no link matching '{a.ref}'"}))
        return 1
    data["links"] = [l for l in data["links"] if l.get("id") != link["id"]]
    data["by_use"], data["by_function"], data["by_scope"] = {}, {}, {}
    for l in data["links"]:
        _bump(data["by_use"], l.get("use", "reference"))
        _bump(data["by_function"], l.get("function", "webpage"))
        _bump(data["by_scope"], l.get("scope", "global"))
    data["updated"] = now_iso()

    archive = load_json(_archive_path(store), {"archived": []})
    link["archived_at"] = now_iso()
    link["archived_reason"] = a.reason or ""
    archive.setdefault("archived", []).append(link)
    save_json_atomic(_archive_path(store), archive)
    save_json_atomic(store.links_file, data)
    store.log(f"ARCHIVE {link['id']} reason={a.reason or '-'}  {link['url']}")
    print(json.dumps({"ok": True, "archived": link["id"], "url": link["url"]}, indent=2))
    return 0


def cmd_restore(store: Store, a) -> int:
    archive = load_json(_archive_path(store), {"archived": []})
    link = _find_link(archive.get("archived", []), a.ref)
    if not link:
        print(json.dumps({"ok": False, "error": f"no archived link matching '{a.ref}'"}))
        return 1
    archive["archived"] = [l for l in archive["archived"] if l.get("id") != link["id"]]
    save_json_atomic(_archive_path(store), archive)
    link.pop("archived_at", None); link.pop("archived_reason", None)
    add_link(store, link["url"], title=link.get("title"), use=link.get("use"),
             function=link.get("function"), scope=link.get("scope", "global"),
             tags=link.get("tags"), source="restore",
             content_file=link.get("content_file"))
    store.log(f"RESTORE {link['id']}  {link['url']}")
    print(json.dumps({"ok": True, "restored": link["id"], "url": link["url"]}, indent=2))
    return 0


def cmd_archived(store: Store, a) -> int:
    archive = load_json(_archive_path(store), {"archived": []})
    items = archive.get("archived", [])
    print(f"Archived links ({len(items)}):")
    for l in items:
        print(f"  {l.get('id')}  [{l.get('use')}]  {l.get('url')}"
              f"   (reason: {l.get('archived_reason') or '-'})")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="knowledge_capture",
                                description="Hemlock global knowledge capture engine")
    p.add_argument("--knowledge-dir", help="override store root")
    sub = p.add_subparsers(dest="cmd", required=True)

    def cls_flags(sp):
        sp.add_argument("--title")
        sp.add_argument("--use")
        sp.add_argument("--function")
        sp.add_argument("--scope", default="global")
        sp.add_argument("--tag", action="append", default=[])
        sp.add_argument("--source", default="manual")
        sp.add_argument("--agent")

    u = sub.add_parser("url"); u.add_argument("url"); cls_flags(u)
    u.add_argument("--fetch", action="store_true", help="opt-in network fetch")
    f = sub.add_parser("file"); f.add_argument("path"); cls_flags(f)
    t = sub.add_parser("text"); cls_flags(t); t.add_argument("--text")
    m = sub.add_parser("message")
    m.add_argument("--text"); m.add_argument("--source", default="gateway")
    m.add_argument("--agent")
    ix = sub.add_parser("index"); ix.add_argument("path")
    s = sub.add_parser("search"); s.add_argument("query", nargs="+")
    ls = sub.add_parser("list")
    ls.add_argument("--links", action="store_true"); ls.add_argument("--docs", action="store_true")
    sub.add_parser("status")
    sub.add_parser("rebuild")

    # Owner management (view / edit / archive / restore) — accept an id or a url.
    sh = sub.add_parser("show"); sh.add_argument("ref")
    ed = sub.add_parser("edit"); ed.add_argument("ref")
    ed.add_argument("--title"); ed.add_argument("--use"); ed.add_argument("--function")
    ed.add_argument("--scope"); ed.add_argument("--add-tag", action="append", default=[])
    ed.add_argument("--del-tag", action="append", default=[])
    ar = sub.add_parser("archive"); ar.add_argument("ref"); ar.add_argument("--reason")
    rs = sub.add_parser("restore"); rs.add_argument("ref")
    sub.add_parser("archived")
    return p


_DISPATCH = {
    "url": cmd_url, "file": cmd_file, "text": cmd_text, "message": cmd_message,
    "index": cmd_index, "search": cmd_search, "list": cmd_list,
    "status": cmd_status, "rebuild": cmd_rebuild,
    "show": cmd_show, "edit": cmd_edit, "archive": cmd_archive,
    "restore": cmd_restore, "archived": cmd_archived,
}


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    store = Store(resolve_knowledge_dir(args.knowledge_dir))
    store.ensure()
    return _DISPATCH[args.cmd](store, args)


if __name__ == "__main__":
    sys.exit(main())
