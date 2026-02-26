FROM openresty/openresty:1.25.3.1-bullseye-fat

# Install Lua dependencies via OpenResty Package Manager (opm)
RUN opm get knyar/nginx-lua-prometheus ledgetech/lua-resty-http

# Copy nginx configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/    /etc/nginx/conf.d/

# Copy Lua modules
COPY lua/       /usr/local/openresty/site/lualib/

EXPOSE 80 9145

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
