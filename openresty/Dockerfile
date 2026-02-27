FROM openresty/openresty:1.25.3.1-bullseye-fat

# Install OTel SDK from GitHub + dependencies from OPM registry
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/* \
 && opm get knyar/nginx-lua-prometheus ledgetech/lua-resty-http \
 && git clone --depth 1 https://github.com/last9/openresty-otel.git /tmp/openresty-otel \
 && cp /tmp/openresty-otel/lua/*.lua /usr/local/openresty/site/lualib/ \
 && rm -rf /tmp/openresty-otel

# Copy nginx configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/    /etc/nginx/conf.d/

EXPOSE 80 9145

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
