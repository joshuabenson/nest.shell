# ═══════════════════════════════════════════════════════════
#  nest.config.sh  -  nest.shell configuration
#  Counterpart to nest-cli.json / nest.config.ts
#  Fun fact: this is valid bash AND valid JSON (it's not)
# ═══════════════════════════════════════════════════════════

# Compiler options (for nestsrv.c)
COMPILER_OPTIONS="-O3 -s"

# Generate options
GENERATE_OPTIONS="--no-dry-run --language=sh"

# Collection (where to find schematics)
COLLECTION="@nestjs/schematics"  # lol, no

# Source root (like NestJS "src/")
SOURCE_ROOT="content"

# Entry file
ENTRY_FILE="nest.sh"

# Monorepo mode
MONOREPO_MODE=false  # we have ONE file

# Assets (files to copy on build)
ASSETS="utils/*.sh"

# Watch assets (for --watch mode)
WATCH_ASSETS="content/**/*.html content/**/*.sh content/**/*.js content/**/*.css"

# Strict mode
STRICT_MODE=true  # set -euo pipefail

# Plugins
PLUGINS=(
    # "@nestjs/swagger" → we have test-suite.sh
    # "@nestjs/typeorm"  → we have sqlite3
    # "@nestjs/throttler" → we have check_rate_limit()
)

# These aren't real, but they feel real:
# compilerOptions:
#   tsConfigPath: tsconfig.json
#   deleteOutDir: true
#   assets: ["**/*.sh"]
#   webpackConfigPath: webpack.config.js
