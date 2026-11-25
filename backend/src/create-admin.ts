/**
 * Creates (or re-activates) an admin account for the dashboard. The password is
 * read from the terminal (never from arguments or files) and stored as argon2id.
 * Two-factor sign-in is set up by the admin on first sign-in.
 *
 *   npm run build && node dist/create-admin.js --email you@example.com --name "Your Name" --role super_admin
 */
import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';
import { createInterface } from 'node:readline';

const ROLES = ['super_admin', 'admin', 'moderator', 'support', 'finance', 'viewer'];

function arg(name: string) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : undefined;
}

function askHidden(q: string): Promise<string> {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    const out = rl as unknown as { _writeToOutput: (s: string) => void; output: NodeJS.WriteStream };
    let shown = false;
    out._writeToOutput = (s: string) => {
      if (!shown) {
        out.output.write(s);
        shown = true;
      }
    };
    rl.question(q, (a) => {
      rl.close();
      process.stdout.write('\n');
      resolve(a);
    });
  });
}

async function main() {
  const email = arg('email')?.trim().toLowerCase();
  const name = arg('name')?.trim();
  const role = arg('role') ?? 'admin';
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !name || !ROLES.includes(role)) {
    console.error(`usage: --email <email> --name "<name>" --role <${ROLES.join('|')}>`);
    process.exit(2);
  }
  const pw = await askHidden('Password (12+ characters): ');
  if (pw.length < 12) throw new Error('Password must be at least 12 characters');
  if ((await askHidden('Repeat password: ')) !== pw) throw new Error('Passwords do not match');
  const prisma = new PrismaClient();
  try {
    const r = await prisma.role.findUnique({ where: { key: role } });
    if (!r) throw new Error(`Role ${role} not found — run the seed first (npm run db:seed)`);
    const passwordHash = await argon2.hash(pw, { type: argon2.argon2id });
    const a = await prisma.adminUser.upsert({
      where: { email },
      create: { email, name, passwordHash },
      update: { name, passwordHash, isActive: true },
    });
    await prisma.adminUserRole.upsert({ where: { adminId_roleId: { adminId: a.id, roleId: r.id } }, create: { adminId: a.id, roleId: r.id }, update: {} });
    console.log(`Admin ${email} (${role}) is ready. Sign in to the dashboard and set up two-factor sign-in.`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
