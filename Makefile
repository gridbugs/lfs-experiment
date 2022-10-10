TAG=ubuntu-lfs

build:
	docker build -t $(TAG) .

run:
	docker run -it --rm $(TAG)

.PHONY: build run
