all:	build


build:
	docker-compose build $(CACHE) oslp
	(unset DOCKER_HOST; dlimg $$BUILD_HOST oslp_oslp)

up:
	(unset DOCKER_HOST ; OSLPCONF=$$PWD/99-oslp.conf docker-compose up --force-recreate oslp)

shell:
	(unset DOCKER_HOST ; docker-compose exec oslp bash ; return 0)


