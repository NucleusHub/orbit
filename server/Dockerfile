FROM node:24-alpine
WORKDIR /app
# ffmpeg/ffprobe: normalise uploaded videos to browser-friendly H.264/AAC MP4
# so they play on mobile browsers too (opt-in per-user via Settings).
RUN apk add --no-cache ffmpeg
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3003
CMD ["sh", "-c", "npm install && node --watch index.js"]
