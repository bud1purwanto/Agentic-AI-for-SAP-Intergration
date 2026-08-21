FROM node:20-bookworm-slim

# Install stunnel4 and basic utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    stunnel4 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency specifications
COPY package*.json tsconfig.json ./
RUN npm install

# Copy application source code and configs
COPY . .
RUN npm run build

# Configure stunnel
RUN mkdir -p /etc/stunnel /var/log/stunnel4 && \
    cp stunnel.conf /etc/stunnel/stunnel.conf && \
    sed -i 's|output = .*|output = /var/log/stunnel4/stunnel.log|' /etc/stunnel/stunnel.conf

# Setup entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["node", "dist/index.js"]
