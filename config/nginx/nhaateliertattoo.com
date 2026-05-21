server {
    listen 80;
    listen [::]:80;
    server_name nhaateliertattoo.com;

    # Cho phep upload file lon (theme, plugin, media)
    client_max_body_size 256M;

    # Proxy vao WordPress Stack (:8888)
    location / {
        proxy_pass http://172.17.0.1:8888;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        # Cloudflare gui HTTPS -> Nginx (HTTP) -> WordPress
        # Phai forward header goc tu Cloudflare, KHONG dung $scheme (se la http)
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    }
}
