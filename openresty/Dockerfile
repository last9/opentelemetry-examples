FROM openresty/openresty:1.25.3.1-bullseye-fat

# Install OTel SDK and dependencies via OPM
RUN opm get last9/openresty-otel knyar/nginx-lua-prometheus

# Copy nginx configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/    /etc/nginx/conf.d/

EXPOSE 80 9145

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
