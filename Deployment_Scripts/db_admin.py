#!/usr/bin/env python3
"""
Safe DB admin helper for the root Makefile's player-maintenance targets
(rank / namechange / create-database).

The Makefile previously interpolated operator-supplied values
(db / group / username / oldname / newname) straight into SQL text, which is a
SQL-injection surface: a value containing a quote or semicolon breaks out of the
statement. This helper removes that:

  * sqlite  -> stdlib sqlite3 with bound '?' parameters (no injection possible).
  * mysql   -> shells out to the `mysql` CLI exactly as before (same -u/user,
               same MYSQL_PWD env, same default socket connection), but builds
               the SQL with correctly escaped string literals and strictly
               validated identifiers.

Identifiers (database names) cannot be bound as parameters in SQL, so they are
validated against a strict allowlist and back-quoted. Numeric inputs (group id)
are validated as integers.

Password: read from the MYSQL_PWD environment variable for the mysql backend,
never passed on the command line.
"""

import argparse
import os
import re
import sqlite3
import subprocess
import sys

_IDENTIFIER = re.compile(r"^[A-Za-z0-9_]+$")


def fail(msg):
    print(">> db_admin: " + msg, file=sys.stderr)
    sys.exit(1)


def validate_identifier(name, label):
    """A schema/database identifier: strict allowlist, cannot be parameterized."""
    if not name or not _IDENTIFIER.match(name):
        fail("invalid %s %r (allowed: letters, digits, underscore)" % (label, name))
    return name


def validate_int(value, label):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        fail("%s must be an integer, got %r" % (label, value))


def mysql_quote(value):
    """Return value as a safely-escaped, single-quoted MySQL string literal.

    Mirrors mysql_real_escape_string for the default (backslash-enabled) mode.
    """
    if value is None:
        return "NULL"
    out = []
    for ch in value:
        if ch == "\x00":
            out.append("\\0")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "'":
            out.append("\\'")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\x1a":
            out.append("\\Z")
        else:
            out.append(ch)
    return "'" + "".join(out) + "'"


def run_mysql(user, sql):
    if "MYSQL_PWD" not in os.environ:
        # Not fatal — mysql can still use a client config or empty password —
        # but warn so it isn't a silent surprise.
        print(">> db_admin: MYSQL_PWD not set in environment", file=sys.stderr)
    cmd = ["mysql", "-u" + user, "-e", sql]
    return subprocess.call(cmd)


def sqlite_path(db):
    validate_identifier(db, "db")
    return os.path.join("server", "inc", "sqlite", db + ".db")


def do_rank(args):
    group = validate_int(args.group, "group")
    if args.backend == "sqlite":
        path = sqlite_path(args.db)
        con = sqlite3.connect(path)
        try:
            con.execute(
                "UPDATE players SET group_id = ? WHERE players.username = ?",
                (group, args.username),
            )
            con.commit()
            print(">> rank: updated %d row(s)" % con.total_changes)
        finally:
            con.close()
        return 0
    db = validate_identifier(args.db, "db")
    sql = "USE `%s`; UPDATE players SET group_id = %d WHERE players.username = %s;" % (
        db, group, mysql_quote(args.username))
    return run_mysql(args.user, sql)


def do_namechange(args):
    if args.backend == "sqlite":
        path = sqlite_path(args.db)
        con = sqlite3.connect(path)
        try:
            con.execute(
                "UPDATE players SET username = ? WHERE players.username = ?",
                (args.newname, args.oldname),
            )
            con.commit()
            print(">> namechange: updated %d row(s)" % con.total_changes)
        finally:
            con.close()
        return 0
    db = validate_identifier(args.db, "db")
    sql = ("USE `%s`; UPDATE players SET username = %s WHERE players.username = %s;"
           % (db, mysql_quote(args.newname), mysql_quote(args.oldname)))
    return run_mysql(args.user, sql)


def do_createdb(args):
    if args.backend != "mysql":
        fail("createdb is only supported for the mysql backend")
    db = validate_identifier(args.db, "db")
    return run_mysql(args.user, "CREATE DATABASE `%s`;" % db)


def main():
    p = argparse.ArgumentParser(description="Safe DB admin helper for the Makefile.")
    p.add_argument("--backend", required=True, choices=["mysql", "sqlite"])
    p.add_argument("--action", required=True, choices=["rank", "namechange", "createdb"])
    p.add_argument("--db", required=True)
    p.add_argument("--user", default="root", help="mysql user (ignored for sqlite)")
    p.add_argument("--group")
    p.add_argument("--username")
    p.add_argument("--oldname")
    p.add_argument("--newname")
    args = p.parse_args()

    if args.action == "rank":
        if args.group is None or args.username is None:
            fail("rank requires --group and --username")
        sys.exit(do_rank(args))
    elif args.action == "namechange":
        if args.oldname is None or args.newname is None:
            fail("namechange requires --oldname and --newname")
        sys.exit(do_namechange(args))
    elif args.action == "createdb":
        sys.exit(do_createdb(args))


if __name__ == "__main__":
    main()
