# syntax=docker/dockerfile:1

# ---- Build stage ---------------------------------------------------------------
FROM node:26-alpine AS build
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --non-interactive
COPY . .
# TMDB key for the browser bundle. Vite inlines VITE_* variables at build time, so the
# key is PUBLIC in the shipped JavaScript. Use a read-only TMDB key dedicated to this app.
ARG TMDB_V3_API_KEY
ENV VITE_APP_TMDB_V3_API_KEY=${TMDB_V3_API_KEY} \
    VITE_APP_API_ENDPOINT_URL=https://api.themoviedb.org/3
RUN yarn build

# ---- Runtime stage: unprivileged nginx -----------------------------------------
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
