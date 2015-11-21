for f in ./ejabberd_modules/*.erl
do
	echo "compiling $f..."
	erlc -I /usr/lib/ejabberd/include -o ./ebin -v $f
done

for f in ./ebin/*
do
	echo "moving $f..."
	cp $f /usr/lib/ejabberd/ebin/
done
