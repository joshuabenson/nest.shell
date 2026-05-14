# 🐚 nest.shell

**A progressive Bash framework for building efficient, reliable, and scalable server-side applications.**

> *"What if NestJS, but it fits in a single shell script and has no `node_modules`?"*

nest.shell is a fully-featured web framework written entirely in Bash. File-system routing, dependency injection (it's just `source`), guards (`.acl` files), pipes (validation scripts), controllers (`.api.sh` files), modules (folders), and a CLI that's honestly funnier than it has any right to be. It ships with a working Todo app, a Guestbook with emoji reactions, OWASP security hardening, Unicode sanitization, a C-based TCP shim, a pre-fork worker pool, and a 43-test test suite. All in under 700 lines of Bash.

It is, simultaneously, the best and worst idea you've ever seen.

---

## 🤔 Why

Because `npm install` shouldn't download half the internet. Because your framework shouldn't be heavier than your application. Because the file system IS a router. Because Bash has been sitting there, quietly, waiting for someone to do something profoundly unwise with it.

And because [NestJS](https://nestjs.com/) is an excellent framework, so excellent that it deserved a parody. The architecture is genuinely similar. The execution is... different.

---

## ⚡ Benchmarks

```
╔══════════════════════════════════════════════════════════╗
║  nest.shell vs The Competition                          ║
╠══════════════════════════════════════════════════════════╣
║                                                         ║
║  nginx (static):      50,000 req/s  ██████████████████  ║
║  bun (elysia):         8,000 req/s  ███                 ║
║  node (express):       5,000 req/s  ██                  ║
║  nest.shell (bash):       17 req/s  ▏                   ║
║                                                         ║
║  "But can it scale?"                                    ║
║  "No. Next question."                                   ║
║                                                         ║
╚══════════════════════════════════════════════════════════╝
```

**Endpoint cost breakdown** (single connection, from `benchmark.sh`):

| Endpoint | Req/sec | Avg latency | What's happening |
|----------|---------|-------------|------------------|
| Static CSS | ~33 | 30ms | Just serving a file |
| `/home` page | ~33 | 30ms | Template + widgets |
| `/todo` page | ~21 | 48ms | Template + SQLite read |
| API: list todos | ~32 | 31ms | SQLite query + JSON |
| API: add todo (POST) | ~20 | 50ms | SQLite write |

**Where the time goes:**

| Operation | Cost |
|-----------|------|
| `fork()` + `exec(bash)` | ~3ms |
| Source 3 utility files | ~2ms |
| Read template from disk | ~8ms |
| Parse HTTP request | ~0.5ms |
| Render nested widgets | ~2ms |
| `sqlite3` subprocess | ~3ms |
| Write log file | ~2ms |
| TCP overhead | ~1ms |

Yes, it's slow. It's Bash. I'm at peace with this. The included `nestsrv.c` (14KB, replaces socat) and `nest-prefork.c` (pre-fork worker pool) can 5× the throughput if you're genuinely unhinged enough to run this in production. Please don't.

---

## 🚀 Quick Start

```bash
# Clone it
git clone https://github.com/yourusername/nest.shell.git
cd nest.shell

# Install dependencies (there are 4 of them, you'll live)
sudo apt install socat jq sqlite3 coreutils

# Start the server
PORT=8080 ./nest.sh

# Or use the CLI (NestJS developers, this will feel familiar)
./nest start
./nest start --watch      # dev mode with auto-reload
npm start                  # it's in package.json, I'm not an animal
```

Open `http://localhost:8080/home`. You'll see the home page. Visit `/todo` for a working CRUD app, `/guestbook` to leave a message with emoji reactions.

---

## 🧠 The Mental Model

nest.shell maps NestJS concepts to the filesystem. If you've used NestJS, you already know the architecture:

```
content/
├── home/                    # @Module({ controllers: [HomeController] })
│   ├── index.html           #     Template (JSX? no. HTML. like a grown-up.)
│   ├── index.js             #     Client-side controller
│   └── style.css            #     Scoped styles
├── todo/                    # @Module({ controllers: [TodoController] })
│   ├── index.html
│   ├── script.sh            #     Server-side render (SSR via Bash. Yes.)
│   └── script.js
├── guestbook/               # @Module({ controllers: [GuestbookController] })
│   └── ...
├── api/
│   └── todo/                # @Controller('/api/todo')
│       ├── list.api.sh      #     @Get('/api/todo/list')
│       ├── add.api.sh       #     @Post('/api/todo/add')
│       ├── toggle.api.sh    #     @Post('/api/todo/toggle')
│       ├── delete.api.sh    #     @Post('/api/todo/delete')
│       └── todo.acl         #     @UseGuards(ApiGuard)
│   └── guestbook/
│       ├── list.api.sh      #     @Get('/api/guestbook/list')
│       └── add.api.sh       #     @Post('/api/guestbook/add')
├── .well-known/
│   └── security.txt         #     RFC 8615 compliance (flex)
├── index.html               #   AppModule template
└── index.js                 #   Global JS (useState, useEffect, widget init)

utils/
├── logs.sh                  # @Injectable() Logger
├── respond.sh               # @Injectable() Response
├── escape.sh                # @Injectable() Sanitizer + ValidationPipe
└── security.sh              # @Injectable() SecurityModule (OWASP-hardened)
```

**Every NestJS concept has a 1:1 shell equivalent:**

| NestJS Concept | nest.shell Equivalent |
|----------------|----------------------|
| `@Module()` | A folder under `content/` |
| `@Controller('/api/todo')` | `content/api/todo/*.api.sh` |
| `@Get()`, `@Post()` | `$HTTP_METHOD` environment variable |
| `@Body()` | `$(cat) \| jq -r '.field'` |
| `@Injectable()` | `source utils/that-file.sh` |
| Dependency Injection | Environment variables piped to subprocesses |
| `@UseGuards(AuthGuard)` | `content/route.acl` (sourced, exit 1 = deny) |
| `@UsePipes(ValidationPipe)` | `is_valid_text()`, `is_positive_int()` |
| `@Module({ imports: [TypeOrmModule] })` | `sqlite3 "$DB_FILE" "SELECT ..."` |
| `nest generate controller cats` | `./nest g controller cats` (yes, this works) |
| `nest start --watch` | `./nest.sh --watch` (inotify-based) |
| `nest build` | `cc -O3 -s -o nestsrv nestsrv.c` |
| `nest test` | `./test-suite.sh` (43 tests, 0 failures) |

---

## 🛠️ CLI

The `nest` CLI provides NestJS-compatible commands:

```bash
# Project scaffolding
./nest new my-app              # Creates a new nest.shell project

# Generate (this is the funniest part)
./nest g controller cats       # content/api/cats/*.api.sh (list, create, get)
./nest g module dashboard      # content/dashboard/index.html + script.js
./nest g service database      # utils/database.sh with CRUD stubs
./nest g guard AdminGuard      # content/AdminGuard.acl
./nest g pipe ValidationPipe   # utils/ValidationPipe.pipe.sh

# Development
./nest start                   # Start the server
./nest start --watch           # Dev mode (auto-reload on file changes)
./nest build                   # Compile C optimizations (nestsrv, nest-prefork)
./nest test                    # Run the 43-test security + functionality suite
./nest info                    # Project statistics (routes, modules, guards...)
```

Or use `npm` if you want to feel professional:
```bash
npm start                      # bash nest.sh
npm run start:dev              # bash nest.sh --watch
npm run build                  # cc -O3 -s -o nestsrv nestsrv.c
npm test                       # bash test-suite.sh
npm run test:bench             # bash benchmark.sh
npm run lint                   # shellcheck everything
npm run generate -- controller cats
```

---

## 🔒 Security (OWASP Hardened)

Because "it's just a hobby project" is not a security posture:

| OWASP Category | What It Does |
|----------------|------------|
| **A01: Broken Access Control** | Path traversal blocked (`..`, `%2e%2e/`), hidden files (`.git`, `.env`) rejected, `.well-known` allowed via RFC 8615 exception |
| **A03: Injection** | SQL: single-quote doubling + SQLi pattern detection logged to `security.log`. XSS: HTML entity escaping on all user output. Unicode: strips zero-width chars, RTLO/bidi overrides, ZWJ, skin tones, BOM, variation selectors. Content-Type enforced for all mutating requests. |
| **A05: Security Misconfiguration** | `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `CSP` with strict directives, `Referrer-Policy`, `Permissions-Policy`, clean `Server` header, no verbose 500 errors |
| **A07: Auth / Rate Limiting** | Token-bucket rate limiter (60 req/min/IP, filesystem-based). `.acl` guard files for route-level auth (`@UseGuards()`). CORS with proper preflight. |
| **A09: Security Logging** | Structured `security.log` with timestamps and severity levels. Logs path traversal attempts, SQLi patterns, rate limit breaches, and suspicious Content-Types. |

Security headers applied to every response:
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' cdn.tailwindcss.com; frame-ancestors 'none'
Server: nest.shell
```

---

## 📦 Dependencies

```
apt install socat jq sqlite3 coreutils
```

That's it. Four dependencies. Not four hundred. Four. Your `node_modules` directory weighs 0 bytes. It doesn't exist. There is no `package-lock.json` with 12,000 lines. There is only Bash, and the quiet satisfaction of knowing your entire toolchain fits in a single screen of `apt install`.

---

## 📂 Project Files

```
nest.shell/
├── nest.sh                    # The framework. 390 lines. That's the whole thing.
├── nest                       # CLI (NestJS-compatible, tongue firmly in cheek)
├── nestsrv.c                  # Custom TCP server in C (14KB, replaces socat)
├── nest-prefork.c             # Pre-fork worker pool (nginx-style architecture)
├── package.json               # Yes, it has one. It's very small. You'll like it.
├── nest.config.sh             # nest-cli.json, but make it bash
│
├── content/                   # Your application. The filesystem IS the router
│   ├── home/                  #   Home module
│   ├── todo/                  #   Todo module (full CRUD demo)
│   ├── guestbook/             #   Guestbook module (emoji reactions!)
│   ├── api/                   #   API controllers
│   ├── .well-known/           #   security.txt
│   └── index.html             #   Root template
│
├── utils/                     # @Injectable() services
│   ├── logs.sh                #   Logging
│   ├── respond.sh             #   HTTP response formatting
│   ├── escape.sh              #   Input sanitization + Unicode stripping
│   └── security.sh            #   OWASP hardening + rate limiting
│
├── test-suite.sh              # 43 tests, 100% pass rate
├── benchmark.sh               # apache bench wrapper
└── app.db                     # SQLite database (auto-created)
```

---

## 🧪 Running Tests

```bash
# Start the server
npm start &

# Run the full test suite
npm test
```

Output:
```
── A01: Broken Access Control (Path Traversal) ──
  ✅ Path traversal blocked (../..)
  ✅ Dot-dot in route blocked
  ✅ Hidden file (.git) blocked
  ✅ .well-known allowed (RFC 8615)
  ✅ Percent-encoded traversal (%2e%2e) blocked

── A03: Injection (SQL, XSS, Unicode) ──
  ✅ SQLi detected & logged
  ✅ XSS: script tags escaped
  ✅ Unicode: zero-width space stripped
  ✅ Unicode: RTLO bidi override stripped
  ✅ Unicode: ZWJ stripped from emoji
  ✅ Unicode: skin tone stripped
  ✅ Unicode: BOM stripped

── A05: Security Headers ──
  ✅ X-Content-Type-Options: nosniff
  ✅ X-Frame-Options: DENY
  ✅ Content-Security-Policy on HTML
  ✅ API: CORS + security headers

── Standard Functionality ──
  ✅ Home / Todo / Guestbook pages (200)
  ✅ 404 page renders
  ✅ CRUD: all operations work
  ✅ Method validation (405 for wrong methods)

═══════════════════════════════════════════════════
  Results: 43 passed, 0 failed
═══════════════════════════════════════════════════
```

---

## 🎯 What This Is

nest.shell is a love letter to:

- **NestJS**, for having such a clean, modular architecture that it's parodiable in Bash
- **Code golf**, for the audacity of fitting a web framework in a shell script
- **The filesystem**, the original router, still undefeated
- **Bash**, for being everywhere, always, quietly capable of things nobody asked it to do
- **Anyone who's ever looked at `node_modules`** and thought "there has to be another way"

It is NOT:
- Fast (17 req/s, I measured)
- Production-ready (please, please don't)
- A replacement for anything (it's a replacement for your afternoon)
- Serious (it has a `--watch` flag implemented with `inotifywait` and a straight face)

---

## 🙃 FAQ

**Q: Can I use this in production?**
A: Technically yes. Morally? That's between you and your incident response team.

**Q: Why Bash?**
A: Because it's on every Unix machine ever made, and nobody was using it for this. Sometimes the best reason to do something is that nobody else is doing it.

**Q: Is this actually like NestJS?**
A: The architecture genuinely is. Modules, controllers, dependency injection, guards, pipes. The patterns are the same. The implementation is... let's call it "resource-constrained."

**Q: Does it scale?**
A: Horizontally, yes. Vertically, also yes. Just not very far up. About 17 requests per second up.

**Q: What's the `nestsrv.c` file?**
A: A 14KB C program that replaces `socat` as the TCP listener. Compiles to a single tiny binary. Zero dependencies. It doesn't make anything faster, but it makes the project 30× more audacious.

**Q: What's `nest-prefork.c`?**
A: An nginx-style worker pool. Persistent Bash workers receive requests via pipes, eliminating `fork()` + `exec()` per request. It's the theoretical 5× speedup. It's also a work in progress. Contributions welcome, especially if they're funny.

**Q: No really, should I use this?**
A: For learning? Absolutely. For a hackathon? Legendary. For a talk at a conference? Instant standing ovation. For anything that handles money, personally identifiable information, or uptime expectations? I beg you, no.

---

## 📄 License

BSD. See [LICENSE](LICENSE).

```
Copyright (c) 2024, someone who looked at node_modules and said "what if bash?"
All rights reserved. Especially the right to be ridiculous.
```
