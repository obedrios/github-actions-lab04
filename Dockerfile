# syntax=docker/dockerfile:1

# ---------------------------------------------------------
# Stage 1 — Build Docusaurus
# ---------------------------------------------------------

FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build


# ---------------------------------------------------------
# Stage 2 — Serve static site with NGINX
# ---------------------------------------------------------

FROM nginx:stable-alpine AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/build /usr/share/nginx/html

EXPOSE 80
