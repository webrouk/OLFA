#!/usr/bin/env python3
"""Checks that prisma/schema.prisma matches the migrated database:
every model maps to a table, every scalar field maps to an existing column with
a compatible type and nullability, and every enum matches the DB enum values.
Usage: PGHOST=… PGPORT=… PGUSER=… python3 test/db/check_prisma_vs_db.py <database>
"""
import os, re, subprocess, sys

db = sys.argv[1]
schema = open(os.path.join(os.path.dirname(__file__), '../../prisma/schema.prisma')).read()

def q(sql):
    out = subprocess.run(['psql', '-d', db, '-qtAF', '|', '-c', sql], capture_output=True, text=True, check=True).stdout
    return [line.split('|') for line in out.strip().splitlines() if line]

cols = {}
for t, c, dt, udt, nullable in q("select table_name, column_name, data_type, udt_name, is_nullable from information_schema.columns where table_schema='public'"):
    cols.setdefault(t, {})[c] = (dt, udt, nullable == 'YES')
db_enums = {}
for name, label in q("select t.typname, e.enumlabel from pg_type t join pg_enum e on e.enumtypid=t.oid order by t.typname, e.enumsortorder"):
    db_enums.setdefault(name, []).append(label)

errors = []
# enums
prisma_enums = {}
for name, body in re.findall(r'^enum (\w+) \{(.*?)^\}', schema, re.M | re.S):
    vals = [l.strip() for l in body.splitlines() if l.strip() and not l.strip().startswith('@@')]
    m = re.search(r'@@map\("(\w+)"\)', body)
    dbname = m.group(1) if m else name
    prisma_enums[name] = dbname
    if db_enums.get(dbname) != vals:
        errors.append(f'enum {name}: prisma {vals} != db {db_enums.get(dbname)}')

TYPE_OK = {
    'String': {'uuid', 'varchar', 'bpchar', 'text'},
    'Int': {'int4', 'int2'}, 'BigInt': {'int8'}, 'Boolean': {'bool'},
    'DateTime': {'timestamptz', 'date'}, 'Json': {'jsonb'},
    'Float': {'float8'}, 'Decimal': {'numeric'}, 'Bytes': {'bytea'},
}
models = re.findall(r'^model (\w+) \{(.*?)^\}', schema, re.M | re.S)
mapped_tables = set()
for name, body in models:
    m = re.search(r'@@map\("(\w+)"\)', body)
    table = m.group(1) if m else name
    mapped_tables.add(table)
    if table not in cols:
        errors.append(f'model {name}: table {table} missing'); continue
    seen = set()
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith('//') or line.startswith('@@'): continue
        parts = line.split()
        field, ftype = parts[0], parts[1]
        base = ftype.rstrip('?').rstrip('[]').rstrip('?')
        is_list = ftype.endswith('[]')
        if base.startswith('Unsupported('):  # e.g. a generated tstzrange column
            cm = re.search(r'@map\("(\w+)"\)', line); seen.add(cm.group(1) if cm else field); continue
        if base not in TYPE_OK and base not in prisma_enums: continue  # relation field
        if '@relation' in line and base not in TYPE_OK: continue
        cm = re.search(r'@map\("(\w+)"\)', line)
        col = cm.group(1) if cm else field
        seen.add(col)
        if col not in cols[table]:
            errors.append(f'{name}.{field}: column {table}.{col} missing'); continue
        dt, udt, nullable = cols[table][col]
        udt_base = udt.lstrip('_')
        if base in prisma_enums:
            if udt_base != prisma_enums[base]: errors.append(f'{name}.{field}: enum {udt} != {prisma_enums[base]}')
        elif udt_base not in TYPE_OK[base]:
            errors.append(f'{name}.{field}: type {base} vs db {udt}')
        if is_list != (dt == 'ARRAY'): errors.append(f'{name}.{field}: list mismatch')
        if (ftype.endswith('?')) != nullable and not is_list:
            errors.append(f'{name}.{field}: nullability prisma={ftype.endswith("?")} db={nullable}')
    for c in cols[table]:
        if c not in seen: errors.append(f'{table}.{c}: column not in Prisma model {name}')

for t in cols:
    if t not in mapped_tables: errors.append(f'table {t} has no Prisma model')

print(f'{len(models)} models, {len(prisma_enums)} enums checked against {len(cols)} tables')
if errors:
    print('\n'.join('  ✗ ' + e for e in errors)); sys.exit(1)
print('  ✓ Prisma schema matches the database')
