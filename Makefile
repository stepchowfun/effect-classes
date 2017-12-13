# Phony targets

.PHONY: \
  all \
  paper lint formalization implementation \
  clean clean-paper clean-formalization clean-implementation \
  docker-deps docker-build

all: paper lint formalization implementation

paper: main.pdf

lint:
	./scripts/check-line-lengths.sh \
	  $(shell \
	    find . \
	      -type d \( \
	        -path ./.git -o \
	        -path ./.github -o \
	        -path ./.paper-build -o \
	        -path ./implementation/.stack-work \
	      \) -prune -o \
	      \( \
		-name '*.hs' -o \
		-name '*.sh' -o \
		-name '*.v' -o \
		-name '*.yml' -o \
		-name 'Dockerfile' -o \
		-name 'Makefile' \
	      \) -print \
	  )

formalization:
	rm -f Makefile.coq _CoqProjectFull
	echo '-R formalization Main' > _CoqProjectFull
	find formalization -type f -name '*.v' >> _CoqProjectFull
	coq_makefile -f _CoqProjectFull -o Makefile.coq || \
	  (rm -f Makefile.coq _CoqProjectFull; exit 1)
	make -f Makefile.coq || \
	  (rm -f Makefile.coq _CoqProjectFull; exit 1)
	rm -f Makefile.coq _CoqProjectFull

implementation:
	cd implementation && \
	  stack build --pedantic --install-ghc --allow-different-user && \
	  stack test --pedantic --install-ghc --allow-different-user

clean: clean-paper clean-formalization clean-implementation

clean-paper:
	rm -rf .paper-build main.pdf

clean-formalization:
	rm -f _CoqProjectFull Makefile.coq \
	  $(shell find . -type f \( \
	    -name '*.glob' -o \
	    -name '*.v.d' -o \
	    -name '*.vo' -o \
	    -name '*.vo.aux' \
	  \) -print)

clean-implementation:
	rm -rf implementation/.stack-work

docker-deps:
	docker build \
	  -f scripts/Dockerfile \
	  -t stephanmisc/delimited-effects:deps \
	  .

docker-build:
	CONTAINER="$$( \
	  docker create \
	    --env "AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID" \
	    --env "AWS_DEFAULT_REGION=$$AWS_DEFAULT_REGION" \
	    --env "AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY" \
	    --env "TRAVIS_BRANCH=$$TRAVIS_BRANCH" \
	    --env "TRAVIS_DEPLOY=$$TRAVIS_DEPLOY" \
	    --env "TRAVIS_PULL_REQUEST=$$TRAVIS_PULL_REQUEST" \
	    --rm \
	    --user=root \
	    stephanmisc/delimited-effects:deps \
	    bash -c ' \
	      chown -R user:user . && \
	      su user -c " \
	        make clean && \
		make && \
		./scripts/travis-deploy.sh \
	      " \
	    ' \
	)" && \
	docker cp . "$$CONTAINER:/home/user/." && \
	docker start --attach "$$CONTAINER"

# The paper

main.pdf: paper/main.tex
	mkdir -p ".paper-build"
	pdflatex \
	  -interaction=nonstopmode \
	  -output-directory ".paper-build" \
	  paper/main.tex
	while ( \
	  grep -qi '^LaTeX Warning: Label(s) may have changed' \
	    '.paper-build/main.log' \
	) do \
	  pdflatex \
	    -interaction=nonstopmode \
	    -output-directory ".paper-build" \
	    paper/main.tex; \
	done
	mv .paper-build/main.pdf .
