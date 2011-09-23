ERLC=/usr/local/bin/erlc
ERLCFLAGS=-o
SRCDIR=.
BEAMDIR=./ebin

compile:
	$(ERLC) $(ERLCFLAGS) $(BEAMDIR) $(SRCDIR)/*.erl ;

run: compile
	erl -pa ./ebin/ -boot start_sasl -s minecraft_server

server_download:
	@mkdir -p server; cd server; test -f minecraft_server.jar || curl -O "https://s3.amazonaws.com/MinecraftDownload/launcher/minecraft_server.jar"

server: server_download
	@cd server; java -Xmx1024M -Xms1024M -jar minecraft_server.jar nogui
