.PHONY: test-ubuntu test-debian test-kali test-all test-security-kali test-clean

DOCKER_BUILD = docker build -f test/Dockerfile

test-ubuntu:
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=ubuntu:24.04 -t dotfiles-test:ubuntu .
	docker run --rm dotfiles-test:ubuntu environment

test-debian:
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=debian:bookworm -t dotfiles-test:debian .
	docker run --rm dotfiles-test:debian environment

test-kali:
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=kalilinux/kali-rolling -t dotfiles-test:kali .
	docker run --rm dotfiles-test:kali environment

test-security-kali:
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=kalilinux/kali-rolling -t dotfiles-test:kali-security .
	docker run --rm dotfiles-test:kali-security security

test-all: test-ubuntu test-debian test-kali

test-clean:
	-docker rmi dotfiles-test:ubuntu dotfiles-test:debian dotfiles-test:kali dotfiles-test:kali-security
