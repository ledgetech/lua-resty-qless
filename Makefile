OPENRESTY_PREFIX=/usr/local/openresty

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install
TEST_FILE ?= t

TEST_REDIS_PORT ?= 6379
TEST_REDIS_DATABASE ?= 6

REDIS_CLI	:= redis-cli -p $(TEST_REDIS_PORT) -n $(TEST_REDIS_DATABASE)

.PHONY: all test install

all: ;

install: all
		$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/resty/qless
			$(INSTALL) lib/resty/qless/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/resty/qless/

test: all
		util/lua-releng
		-@echo "Flushing Redis DB"
		@$(REDIS_CLI) flushdb
		@rm -f luacov.stats.out
		PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH TEST_REDIS_DATABASE=$(TEST_REDIS_DATABASE) TEST_REDIS_PORT=$(TEST_REDIS_PORT) TEST_NGINX_NO_SHUFFLE=1 prove -I../test-nginx/lib -r $(TEST_FILE)
		@luacov
		@tail -14 luacov.report.out
