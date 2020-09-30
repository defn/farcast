version: "3.7"

_zerotiers: [ "zerotier0", "zerotier1", "zerotier2"]

_zones: [ "1", "2"]

_ip_global: "192.168.195.156"

_zerotier: {
	image:    "letfn/zerotier"
	env_file: ".env"
	volumes: [...]
	cap_drop: [
		"NET_RAW",
		"NET_ADMIN",
		"SYS_ADMIN",
	]
	devices: [
		"/dev/net/tun",
	]
	privileged: true
}

_kuma_global: {
	image:        "letfn/kuma"
	network_mode: "service:zerotier0"
	entrypoint: [
		"kuma-cp",
		"run",
	]
	env_file: ".env"
	environment: [
		"KUMA_MODE=global",
	]
	volumes: [
		"config:/config",
	]
}

_kuma_cp: [N=_]: {
	image: "letfn/kuma"
	entrypoint: [
		"kuma-cp",
		"run",
	]
	env_file: ".env"
	environment: [
		"KUMA_MODE=remote",
		"KUMA_MULTICLUSTER_REMOTE_ZONE=farcast\(N)",
		"KUMA_MULTICLUSTER_REMOTE_GLOBAL_ADDRESS=grpcs://\(_ip_global):5685",
		"KUMA_GENERAL_ADVERTISED_HOSTNAME=kuma-cp\(N)",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_ENABLED=true",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_INTERFACE=0.0.0.0",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_PORT=5684",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_TLS_CERT_FILE=/certs/server/cert.pem",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_TLS_KEY_FILE=/certs/server/key.pem",
		"KUMA_DATAPLANE_TOKEN_SERVER_PUBLIC_CLIENT_CERTS_DIR=/certs/client",
	]
	volumes: [
		"config:/config",
	]
}

_kuma_ingress: [N=_]: {
	image:        "letfn/kuma"
	network_mode: "service:zerotier\(N)"
	entrypoint: [
		"kuma-dp",
		"run",
		"--name=kuma-ingress",
		"--cp-address=http://kuma-cp\(N):5681",
		"--dataplane-token-file=/config/farcast\(N)-ingress-token",
		"--log-level=debug",
	]
	volumes: [
		"config:/config",
	]
}

_kuma_app_pause: {
	image: "gcr.io/google_containers/pause-amd64:3.2"
}

_kuma_app: [N=_]: {
	image:        "nginx"
	network_mode: "service:kuma-app\(N)-pause"
	volumes: [
		"config:/config",
	]
}

_kuma_app_dp: [N=_]: {
	image:        "letfn/kuma"
	network_mode: "service:kuma-app\(N)-pause"
	entrypoint: [
		"kuma-dp",
		"run",
		"--name=app",
		"--cp-address=http://kuma-cp\(N):5681",
		"--dataplane-token-file=/config/farcast\(N)-app-token",
		"--log-level=debug",
	]
	volumes: [
		"config:/config",
	]
}

_init: {
	image: "ubuntu"
	command: [
		"bash",
		"-c",
		"""
		set -x
		exec sleep 86400000

		""",
	]

	volumes: [
		"config:/config",
		"zerotier0:/zerotier0",
		"zerotier1:/zerotier1",
		"zerotier2:/zerotier2",
	]
	healthcheck: {
		test: ["CMD", "test", "-f", "/tmp/done.txt"]
		interval: "10s"
		timeout:  "15s"
		retries:  100
	}
}

_sshd: {
	image:        "defn/home:jojomomojo"
	network_mode: "service:init"
	entrypoint: ["/service", "sshd"]
	env_file: ".env"
	volumes: [
		"/var/run/docker.sock:/var/run/docker.sock",
		"config:/data/home-secret",
		"config:/config",
		"zerotier0:/zerotier0",
		"zerotier1:/zerotier1",
		"zerotier2:/zerotier2",
	]
}

_cloudflared: {
	image:        "letfn/cloudflared"
	network_mode: "service:init"
	env_file:     ".env"
	volumes: [
		"config:/app/src/.cloudflared",
	]
}

services: {
	init: _init

	sshd: _sshd
	sshd: depends_on: init: condition: "service_healthy"

	cloudflared: _cloudflared
	cloudflared: depends_on: init: condition: "service_healthy"

	"kuma-global": _kuma_global
	"kuma-global": depends_on: {
		init: condition: "service_healthy"
		{
			for n in _zerotiers {
				"\(n)": condition: "service_started"
			}
		}
	}

	{
		for n in _zones {
			"kuma-cp-\(n)": (_kuma_cp & {"\(n)": {}})[n]
			"kuma-cp-\(n)": depends_on: "kuma-global": condition: "service_started"

			"kuma-ingress-\(n)": (_kuma_ingress & {"\(n)": {}})[n]
			"kuma-ingress-\(n)": depends_on: "kuma-cp-\(n)": condition: "service_started"

			"kuma-app-dp-\(n)": (_kuma_app_dp & {"\(n)": {}})[n]
			"kuma-app-dp-\(n)": depends_on: "kuma-cp-\(n)": condition: "service_started"

			"kuma-app-pause-\(n)": _kuma_app_pause

			"kuma-app-\(n)": (_kuma_app & {"\(n)": {}})[n]
		}
	}

	{
		for n in _zerotiers {
			"\(n)": _zerotier & {
				volumes: [
					"\(n):/var/lib/zerotier-one",
					"config:/service.d",
				]

				depends_on: init: condition: "service_healthy"
			}
		}
	}

}

volumes: {
	config: {}
	{
		for n in _zerotiers {
			"\(n)": {}
		}
	}
}
