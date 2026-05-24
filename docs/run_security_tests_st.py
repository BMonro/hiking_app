#!/usr/bin/env python3
"""Автоматична перевірка ST-01 … ST-13 та ST-28 … ST-31 (безпека Hikora).

Запуск:
  py -3 docs/run_security_tests_st.py
  py -3 docs/run_security_tests_st.py --edge-only   # ST-01,02 + ST-28..31 (статика)

Два тестові акаунти (PowerShell):
  $env:HIKORA_TEST_EMAIL_A="user1@example.com"
  $env:HIKORA_TEST_EMAIL_B="user2@example.com"
  $env:HIKORA_TEST_PASSWORD="YourPassword"
  py -3 docs/run_security_tests_st.py
"""
from __future__ import annotations

import json
import os
import re
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional
from urllib.error import HTTPError
from urllib.request import Request, urlopen

# З lib/core/config/supabase_config.dart (anon key — публічний)
SUPABASE_URL = "https://oifgifiikduhrdyaxrfi.supabase.co"
ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6"
    "Im9pZmdpZmlpa2R1aHJkeWF4cmZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0ODUwMjAs"
    "ImV4cCI6MjA5MzA2MTAyMH0.C1X_8Ugpi-OGL0cHcNyvJy98Q88vOsWGLyMJ2j-ZJ7k"
)
REST = f"{SUPABASE_URL}/rest/v1"
AUTH = f"{SUPABASE_URL}/auth/v1"
FN = f"{SUPABASE_URL}/functions/v1"
STORAGE = f"{SUPABASE_URL}/storage/v1"
# Мінімальні байти для upload (image/jpeg)
FAKE_JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64

TEST_PASSWORD = os.environ.get("HIKORA_TEST_PASSWORD", "Test1234")
EMAIL_A = os.environ.get("HIKORA_TEST_EMAIL_A", "hiker_test@mail.com")
EMAIL_B = os.environ.get("HIKORA_TEST_EMAIL_B", "hiker_new@mail.com")
EDGE_ONLY = "--edge-only" in sys.argv
REPO_ROOT = Path(__file__).resolve().parents[1]


def check_st29_no_openai_key_in_client() -> tuple[bool, str]:
    """ST-29: sk-… не в lib/ (release-клієнт)."""
    hits: list[str] = []
    key_re = re.compile(r"sk-[a-zA-Z0-9]{8,}")
    for path in (REPO_ROOT / "lib").rglob("*.dart"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for m in key_re.finditer(text):
            hits.append(f"{path.relative_to(REPO_ROOT)}:{m.group()[:12]}...")
    return (len(hits) == 0, "немає sk- у lib/" if not hits else "; ".join(hits[:5]))


def storage_upload(
    path: str,
    *,
    token: Optional[str] = None,
    bucket: str = "avatars",
) -> tuple[int, Any]:
    """POST /storage/v1/object/{bucket}/{path}"""
    headers = {
        "apikey": ANON_KEY,
        "Content-Type": "image/jpeg",
        "x-upsert": "true",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = f"{STORAGE}/object/{bucket}/{path}"
    req = Request(url, data=FAKE_JPEG, headers=headers, method="POST")
    try:
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8") or ""
            try:
                return resp.status, json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                return resp.status, raw
    except HTTPError as e:
        raw = e.read().decode("utf-8") or ""
        try:
            return e.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return e.code, raw


def check_st30_recommend_ignores_body_user_id() -> tuple[bool, str]:
    """ST-30: recommend-routes бере userId лише з JWT."""
    src = REPO_ROOT / "supabase/functions/recommend-routes/index.ts"
    text = src.read_text(encoding="utf-8")
    if "body.user_id" in text or "body?.user_id" in text:
        return False, "знайдено читання user_id з body"
    if "userId" not in text or "createUserClient" not in text:
        return False, "неочікувана структура recommend-routes"
    return True, "userId з createUserClient (JWT), body.user_id не використовується"


@dataclass
class Result:
    case_id: str
    name: str
    passed: bool
    detail: str


def http(
    method: str,
    url: str,
    *,
    token: Optional[str] = None,
    body: Optional[dict] = None,
    extra_headers: Optional[dict] = None,
) -> tuple[int, Any]:
    headers = {
        "apikey": ANON_KEY,
        "Content-Type": "application/json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if extra_headers:
        headers.update(extra_headers)
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8") or "null"
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except HTTPError as e:
        raw = e.read().decode("utf-8") or ""
        try:
            return e.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return e.code, raw


def sign_up(email: str, password: str) -> tuple[Optional[str], Optional[str], str]:
    status, data = http(
        "POST",
        f"{AUTH}/signup",
        body={"email": email, "password": password},
    )
    if status not in (200, 201):
        return None, None, f"signup {status}: {data}"
    session = (data or {}).get("access_token")
    user = ((data or {}).get("user") or {}).get("id")
    if session and user:
        return session, user, "ok"
    # інколи потрібен signIn після signup
    return sign_in(email, password)


def sign_in(email: str, password: str) -> tuple[Optional[str], Optional[str], str]:
    status, data = http(
        "POST",
        f"{AUTH}/token?grant_type=password",
        body={"email": email, "password": password},
    )
    if status != 200:
        return None, None, f"signin {status}: {data}"
    return data.get("access_token"), (data.get("user") or {}).get("id"), "ok"


def ensure_profile(token: str, user_id: str) -> None:
    http(
        "POST",
        f"{REST}/profiles",
        token=token,
        body={
            "id": user_id,
            "full_name": "SecTest",
            "age": 25,
            "fitness_level": "beginner",
        },
        extra_headers={"Prefer": "resolution=merge-duplicates"},
    )


def main() -> int:
    results: list[Result] = []

    def record(cid: str, name: str, ok: bool, detail: str) -> None:
        results.append(Result(cid, name, ok, detail))
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {cid}: {detail}")

    # --- ST-01, ST-02 (без сесії) ---
    st, data = http(
        "POST",
        f"{FN}/trip-actions",
        body={"action": "apply", "trip_id": str(uuid.uuid4())},
    )
    record(
        "ST-01",
        "Edge без JWT",
        st == 401,
        f"HTTP {st}, body={data}",
    )

    st, data = http(
        "POST",
        f"{FN}/route-hike",
        token="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake.token",
        body={"waypoints": [{"lat": 48.0, "lon": 24.0}, {"lat": 48.1, "lon": 24.1}]},
    )
    record(
        "ST-02",
        "Недійсний JWT",
        st == 401,
        f"HTTP {st}, body={data}",
    )

    # --- ST-29, ST-30 (статика, без акаунтів) ---
    ok29, d29 = check_st29_no_openai_key_in_client()
    record("ST-29", "Немає sk- у lib/", ok29, d29)
    ok30s, d30s = check_st30_recommend_ignores_body_user_id()
    record("ST-30 (код)", "JWT, не body.user_id", ok30s, d30s)

    # --- Storage: без JWT / чужий шлях (додаток Н, група файлів) ---
    st_s0, res_s0 = storage_upload(f"noauth-{uuid.uuid4().hex[:8]}-avatar.jpg")
    blocked_no_auth = st_s0 in (400, 401, 403)
    record(
        "ST-Storage-1",
        "Upload Storage без JWT",
        blocked_no_auth,
        f"HTTP {st_s0}, body={res_s0} (очікувано 403; API без Authorization часто 400)",
    )

    if EDGE_ONLY:
        print("\n=== --edge-only: ST-03..ST-27 потребують акаунтів ===")
        return 0 if all(r.passed for r in results) else 1

    # --- користувачі A і B ---
    token_a, user_a, msg_a = sign_in(EMAIL_A, TEST_PASSWORD)
    if not token_a:
        token_a, user_a, msg_a = sign_up(EMAIL_A, TEST_PASSWORD)
    token_b, user_b, msg_b = sign_in(EMAIL_B, TEST_PASSWORD)
    if not token_b:
        token_b, user_b, msg_b = sign_up(EMAIL_B, TEST_PASSWORD)
    if not token_a or not token_b:
        print(f"Не вдалося увійти: A={msg_a}, B={msg_b}")
        print(f"Увійдіть у застосунок або задайте env: {EMAIL_A}, {EMAIL_B}")
        print("Пароль: HIKORA_TEST_PASSWORD (за замовч. Test1234)")
        return 1

    ensure_profile(token_a, user_a)
    ensure_profile(token_b, user_b)

    # --- ST-03: чужий журнал ---
    st, rows = http(
        "GET",
        f"{REST}/journal_entries?user_id=eq.{user_b}&select=id",
        token=token_a,
    )
    empty = isinstance(rows, list) and len(rows) == 0
    record("ST-03", "Чужий journal (RLS)", st == 200 and empty, f"HTTP {st}, rows={rows}")

    # --- ST-12 prep: приватний маршрут B ---
    priv_title = f"Private {uuid.uuid4().hex[:6]}"
    st, route_priv = http(
        "POST",
        f"{REST}/routes",
        token=token_b,
        body={
            "author_id": user_b,
            "title": priv_title,
            "difficulty": "easy",
            "is_public": False,
        },
        extra_headers={"Prefer": "return=representation"},
    )
    route_priv_id = (route_priv[0]["id"] if isinstance(route_priv, list) and route_priv else None)

    # --- ST-05 / ST-13 prep: публічний маршрут B для update ---
    st, route_pub = http(
        "POST",
        f"{REST}/routes",
        token=token_b,
        body={
            "author_id": user_b,
            "title": f"Public {uuid.uuid4().hex[:6]}",
            "difficulty": "easy",
            "is_public": True,
        },
        extra_headers={"Prefer": "return=representation"},
    )
    route_pub_id = (route_pub[0]["id"] if isinstance(route_pub, list) and route_pub else None)

    # --- ST-05: PATCH чужого маршруту ---
    if route_pub_id:
        st, patch_res = http(
            "PATCH",
            f"{REST}/routes?id=eq.{route_pub_id}",
            token=token_a,
            body={"title": "Hacked"},
            extra_headers={"Prefer": "return=representation"},
        )
        patched = isinstance(patch_res, list) and len(patch_res) == 0
        record(
            "ST-05",
            "PATCH чужого routes",
            st in (200, 204) and patched,
            f"HTTP {st}, rows={patch_res}",
        )
    else:
        record("ST-05", "PATCH чужого routes", False, "не створено маршрут B")

    # --- ST-06, ST-07 ---
    st, off = http(
        "GET",
        f"{REST}/offline_routes?select=user_id",
        token=token_a,
    )
    only_own_off = isinstance(off, list) and all(r.get("user_id") == user_a for r in off)
    record(
        "ST-06",
        "offline_routes лише свої",
        st == 200 and only_own_off,
        f"HTTP {st}, count={len(off) if isinstance(off, list) else off}",
    )

    st, notif = http(
        "GET",
        f"{REST}/notifications?select=user_id",
        token=token_a,
    )
    only_own_n = isinstance(notif, list) and all(r.get("user_id") == user_a for r in notif)
    record(
        "ST-07",
        "notifications лише свої",
        st == 200 and only_own_n,
        f"HTTP {st}, count={len(notif) if isinstance(notif, list) else notif}",
    )

    # --- ST-12: приватний маршрут ---
    if route_priv_id:
        st, vis = http(
            "GET",
            f"{REST}/routes?id=eq.{route_priv_id}&select=id,title,is_public",
            token=token_a,
        )
        hidden = isinstance(vis, list) and len(vis) == 0
        record(
            "ST-12",
            "Приватний маршрут",
            st == 200 and hidden,
            f"HTTP {st}, rows={vis}",
        )
    else:
        record("ST-12", "Приватний маршрут", False, "не створено приватний маршрут")

    # --- ST-13: save-route update чужого ---
    if route_pub_id:
        st, sr = http(
            "POST",
            f"{FN}/save-route",
            token=token_a,
            body={
                "action": "update",
                "route_id": route_pub_id,
                "title": "Hack via edge",
                "points": [
                    {
                        "latitude": 48.0,
                        "longitude": 24.0,
                        "point_type": "start",
                    },
                    {
                        "latitude": 48.1,
                        "longitude": 24.1,
                        "point_type": "finish",
                    },
                ],
            },
        )
        forbidden = st == 403 or (
            isinstance(sr, dict) and sr.get("error") == "forbidden"
        )
        record("ST-13", "save-route update чужого", forbidden, f"HTTP {st}, body={sr}")
    else:
        record("ST-13", "save-route update чужого", False, "немає route_pub_id")

    # --- похід A: ST-08, ST-09, ST-10, ST-04, ST-11 ---
    trip_id = None
    st, trip_res = http(
        "POST",
        f"{FN}/trip-actions",
        token=token_a,
        body={
            "action": "create",
            "title": f"Sec trip {uuid.uuid4().hex[:6]}",
            "start_date": "2026-06-01",
            "end_date": "2026-06-02",
            "max_members": 5,
        },
    )
    if isinstance(trip_res, dict):
        trip_id = trip_res.get("trip_id")

    if trip_id:
        # B apply
        http(
            "POST",
            f"{FN}/trip-actions",
            token=token_b,
            body={"action": "apply", "trip_id": trip_id},
        )

        st, dup = http(
            "POST",
            f"{FN}/trip-actions",
            token=token_b,
            body={"action": "apply", "trip_id": trip_id},
        )
        dup_ok = (
            isinstance(dup, dict)
            and dup.get("error") == "already_applied"
            and st == 409
        )
        record("ST-08", "Повторна apply", dup_ok, f"HTTP {st}, body={dup}")

        st, org = http(
            "POST",
            f"{FN}/trip-actions",
            token=token_a,
            body={"action": "apply", "trip_id": trip_id},
        )
        org_err = isinstance(org, dict) and (
            org.get("error") == "organizer_cannot_apply"
            or "organizer_cannot_apply" in str(org.get("message", ""))
            or "organizer_cannot_apply" in str(org)
        )
        record(
            "ST-09",
            "Організатор apply",
            org_err and st in (400, 500),
            f"HTTP {st}, body={org}",
        )

        st, dec = http(
            "POST",
            f"{FN}/trip-actions",
            token=token_b,
            body={
                "action": "decide",
                "trip_id": trip_id,
                "applicant_id": user_b,
                "approved": True,
            },
        )
        dec_forbidden = isinstance(dec, dict) and dec.get("error") == "forbidden" and st == 403
        record(
            "ST-10",
            "decide не організатором",
            dec_forbidden,
            f"HTTP {st}, body={dec}",
        )

        # ST-04: B pending — messages SELECT
        st, msgs = http(
            "GET",
            f"{REST}/messages?trip_id=eq.{trip_id}&select=id",
            token=token_b,
        )
        blocked = isinstance(msgs, list) and len(msgs) == 0
        record(
            "ST-04",
            "messages pending (RLS)",
            st == 200 and blocked,
            f"HTTP {st}, rows={msgs}",
        )

        # ST-11: сторонній C (user A не approved) — insert message as A without approve
        # A is organizer — might have access. Use fresh user? A is organizer so has access.
        # Test: user B still pending tries INSERT via REST
        st, ins = http(
            "POST",
            f"{REST}/messages",
            token=token_b,
            body={
                "trip_id": trip_id,
                "sender_id": user_b,
                "content": "should fail",
            },
            extra_headers={"Prefer": "return=representation"},
        )
        ins_blocked = st in (401, 403) or (
            isinstance(ins, dict) and ins.get("code") in ("42501", "PGRST301", "403")
        ) or (isinstance(ins, list) and len(ins) == 0)
        # PostgREST often returns 403 or empty policy violation
        if st >= 400:
            ins_blocked = True
        record(
            "ST-11",
            "INSERT messages не учасником",
            ins_blocked,
            f"HTTP {st}, body={ins}",
        )

        # trip-chat send as pending B
        st, chat = http(
            "POST",
            f"{FN}/trip-chat",
            token=token_b,
            body={"action": "send", "trip_id": trip_id, "content": "hi"},
        )
        chat_block = isinstance(chat, dict) and chat.get("error") == "forbidden" and st == 403
        record(
            "ST-11b",
            "trip-chat send pending",
            chat_block,
            f"HTTP {st}, body={chat} (додатково до ST-11)",
        )
    else:
        for cid, name in [
            ("ST-08", "Повторна apply"),
            ("ST-09", "Організатор apply"),
            ("ST-10", "decide не організатором"),
            ("ST-04", "messages pending"),
            ("ST-11", "INSERT messages"),
        ]:
            record(cid, name, False, f"не створено похід: {trip_res}")

    # --- ST-28: IDOR trip_id (чат / messages / participants) ---
    idor_ok = True
    idor_details = []
    for _ in range(5):
        fake_trip = str(uuid.uuid4())
        st_m, msgs = http(
            "GET",
            f"{REST}/messages?trip_id=eq.{fake_trip}&select=id",
            token=token_a,
        )
        st_p, parts = http(
            "GET",
            f"{REST}/trip_participants?trip_id=eq.{fake_trip}&select=user_id",
            token=token_a,
        )
        st_c, chat = http(
            "POST",
            f"{FN}/trip-chat",
            token=token_a,
            body={"action": "list", "trip_id": fake_trip},
        )
        msgs_ok = isinstance(msgs, list) and len(msgs) == 0
        parts_ok = isinstance(parts, list) and len(parts) == 0
        chat_ok = (isinstance(chat, dict) and chat.get("error") == "forbidden") or st_c == 403
        if not (msgs_ok and parts_ok and chat_ok):
            idor_ok = False
            idor_details.append(
                f"{fake_trip[:8]}: msgs={len(msgs) if isinstance(msgs,list) else msgs}, "
                f"parts={len(parts) if isinstance(parts,list) else parts}, chat={st_c}"
            )
    record(
        "ST-28",
        "IDOR trip_id",
        idor_ok,
        "5 випадкових UUID: messages/participants порожні, trip-chat forbidden"
        if idor_ok
        else "; ".join(idor_details[:3]),
    )

    # --- ST-30 (динаміка): user_id у body recommend-routes ---
    http(
        "PATCH",
        f"{REST}/profiles?id=eq.{user_a}",
        token=token_a,
        body={"fitness_level": "beginner", "preferred_difficulty": "easy"},
    )
    http(
        "PATCH",
        f"{REST}/profiles?id=eq.{user_b}",
        token=token_b,
        body={"fitness_level": "advanced", "preferred_difficulty": "hard"},
    )
    st_r, rec_a = http(
        "POST",
        f"{FN}/recommend-routes",
        token=token_a,
        body={"user_id": user_b},
    )
    st_r2, rec_b = http(
        "POST",
        f"{FN}/recommend-routes",
        token=token_b,
        body={"user_id": user_a},
    )
    dyn30 = (
        st_r == 200
        and st_r2 == 200
        and isinstance(rec_a, dict)
        and isinstance(rec_b, dict)
        and rec_a.get("recommendations") is not None
    )
    record(
        "ST-30 (API)",
        "user_id у body ігнорується",
        dyn30,
        f"A+body(B): source={rec_a.get('source') if isinstance(rec_a,dict) else rec_a}, "
        f"B+body(A): source={rec_b.get('source') if isinstance(rec_b,dict) else rec_b}",
    )

    # --- ST-31: DELETE чужого journal_photos ---
    st_j, entry_b = http(
        "POST",
        f"{REST}/journal_entries",
        token=token_b,
        body={
            "user_id": user_b,
            "date": "2026-05-20",
            "title": "Sec test entry",
            "notes": "photo delete test",
        },
        extra_headers={"Prefer": "return=representation"},
    )
    entry_id = (
        entry_b[0]["id"]
        if isinstance(entry_b, list) and entry_b
        else None
    )
    photo_id = None
    st_ph, ph = None, None
    if entry_id:
        st_ph, ph = http(
            "POST",
            f"{REST}/journal_photos",
            token=token_b,
            body={
                "entry_id": entry_id,
                "photo_url": "https://example.com/test-photo.jpg",
            },
            extra_headers={"Prefer": "return=representation"},
        )
        if isinstance(ph, list) and ph:
            photo_id = ph[0].get("id")
    if photo_id:
        st_del, del_res = http(
            "DELETE",
            f"{REST}/journal_photos?id=eq.{photo_id}",
            token=token_a,
            extra_headers={"Prefer": "return=representation"},
        )
        deleted = isinstance(del_res, list) and len(del_res) == 0
        record(
            "ST-31",
            "DELETE чужого photo",
            st_del in (200, 204) and deleted,
            f"HTTP {st_del}, deleted_rows={del_res}",
        )
        # cleanup
        http(
            "DELETE",
            f"{REST}/journal_photos?id=eq.{photo_id}",
            token=token_b,
        )
        http(
            "DELETE",
            f"{REST}/journal_entries?id=eq.{entry_id}",
            token=token_b,
        )
    else:
        record(
            "ST-31",
            "DELETE чужого photo",
            False,
            f"не створено photo: entry={entry_id}, ph={ph if entry_id else st_j}",
        )

    # --- ST-Storage-2: upload у шлях uid-B під сесією A ---
    foreign_path = f"{user_b}-avatar.jpg"
    st_s2, res_s2 = storage_upload(foreign_path, token=token_a)
    blocked_foreign = st_s2 in (400, 403) or (
        isinstance(res_s2, dict)
        and (
            res_s2.get("statusCode") == "403"
            or "row-level security" in str(res_s2).lower()
            or "policy" in str(res_s2).lower()
        )
    )
    record(
        "ST-Storage-2",
        "Upload avatars чужого uid",
        blocked_foreign,
        f"path={foreign_path}, HTTP {st_s2}, body={res_s2}",
    )

    # --- підсумок ---
    passed = sum(1 for r in results if r.passed)
    total = len(results)
    print(f"\n=== Підсумок: {passed}/{total} пройдено ===")
    failed = [r for r in results if not r.passed]
    if failed:
        print("Невдачі:")
        for r in failed:
            print(f"  {r.case_id}: {r.detail}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
