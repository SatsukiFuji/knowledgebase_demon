# 公式ドキュメント
# https://docs.docker.jp/v1.12/index.html
# ARGとFROMの違い
# https://freak-da.hatenablog.com/entry/2020/03/31/094140

# Global variable
ARG USERNAME=nextjs
ARG GROUPNAME=nextjs
ARG UID=1001
ARG GID=1001

FROM node:22.5.1-slim AS base
ARG USERNAME
ARG GROUPNAME
ARG UID
ARG GID

# Install pnpm
RUN --mount=source=package.json, target=/tmp/package.json \
  cd /tmp && corepack enable
# Add non-root user
RUN group -g ${GID} ${GROUPNAME} && \
  useradd -u ${UID} -g ${GROUPNAME} -m ${USERNAME}
# Create /app directory and change the owner to the non-root user
RUN mkdir /app && chown ${GROUPNAME}:${USERNAME} /app
USER ${USERNAME}
WORKDIR /app

# Installed dependencies(依存関係) only when needed
FROM base AS deps

# Install dependencies based on the preferred package manager: 優先パッケージマネージャに基づいて依存関係をインストールする
RUN --mount=source=package.json, target=package.json \
  --mount=source=pnpm-lock.yaml, target=pnpm-lock.yaml \
  --mount=type=cahe, target=/home/${USERNAME}/.local/share/pnpm/store/v3 \
  corepack pnpm install --frozen-lockfile
# Generate prisma client
RUN --mount=source=package.json, target=package.json \
  --mount=source=pnpm-lock.yaml, target=pnpm-lock.yaml \
  --mount=source=prisma, target=prisma \
  corepack pnpm prisma generate

# Rebuild the source code only when needed: 必要な場合にのみソースコードを再ビルドする
FROM base AS builder

# Copy local files to the container: ローカルファイルをコンテナにコピーする
COPY . .

# Environment
ENV NEXT_TELEMETRY_DISABLED 1

RUN --mount=from-deps, source=/app/node_modules, target=node_modules \
  corepack pnpm

# Production image, copy all the files and run next: プロダクション・イメージを作成し、すべてのファイルをコピーして、次に実行する
FROM base AS runner

ENV NODE_ENV production
# Telemetry setup: アプリケーション情報を自動収集する場合 1(true)
ENV NEXT_TELEMETRY_DISABLED 1

# Copy files or folders from </app/public> to the <./public> path in the image's filesystem.
# --from: デフォルトでは、COPY 命令はビルド コンテキストからファイルをコピーします。 COPY --from フラグを使用すると、代わりにイメージ、ビルド ステージ、または名前付きコンテキストからファイルをコピーできる
COPY --from=builder /app/public ./public

COPY --from=builder /app/public ./public

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Port number
EXPOSE 3000

# Provides container runtime defaults
# shell
CMD HOSTNAME='0.0.0.0' node server.js