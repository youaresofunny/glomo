-module(mod_iq_register).

-behaviour(ejabberd_config).

-behaviour(gen_mod).

-define(NS_REG, <<"jabber:iq:register_phone">>).
-define(NS_CONFIRM, <<"jabber:iq:confirm_phone">>).
-define(DOMAIN, <<"localhost">>).
-define(SMS_BASE_URL, "http://10.20.254.4:13002/cgi-bin/sendsms?username=kanneluser&password=kannelpass&smsc=mitto&from=Glomo.im&to=").
-define(ALLOWED_CHARS, [$0,$1,$2,$3,$4,$5,$6,$7,$8,$9,$a,$b,$c,$d,$e,$f,$g,$h,$i,$j,$k,$l,$m,$n,$o,$p,$q,$r,$s,$t,$u,$v,$w,$x,$y,$z]).

-export([start/2, 
	 stop/1, 
	 unauthenticated_iq/4]).

-export([random_password/1, random_char/0]).

-include("ejabberd.hrl").
-include("logger.hrl").
-include("jlib.hrl").
-include("mod_privacy.hrl").

-record(user_countries,{user= <<"">>, country = <<"">>}).

random_char() ->
	Val = random:uniform(length(?ALLOWED_CHARS)),
	lists:nth(Val, ?ALLOWED_CHARS).

random_password(0) -> 
	[];
random_password(N) ->
	[random_char()|random_password(N-1)].

start(Host, Opts) ->
	mnesia:create_table(user_countries,
		[{disc_copies, [node()]},
		 {attributes,
		  record_info(fields, user_countries)}]),
	ejabberd_hooks:add(c2s_unauthenticated_iq, Host, ?MODULE, unauthenticated_iq, 50),
	inets:start(),
	ok.

stop(Host) ->
	ejabberd_hooks:delete(c2s_unauthenticated_iq, Host,?MODULE, unauthenticated_iq_register, 50).


unauthenticated_iq(Acc, Server, #iq{xmlns = ?NS_REG, sub_el = SubEl} = IQ, IP) -> 
	PhoneTag = xml:get_subtag(SubEl, <<"phone">>),
	if 
		(PhoneTag /= false)->

			{xmlel,_,_,PhoneChildren} = PhoneTag,
			PhoneNumber = xml:get_cdata(PhoneChildren),
			BinPhone = binary:bin_to_list(PhoneNumber),

			FormattedPhone = mod_number_lookup:format_phone(PhoneNumber),

			NewPasswd = list_to_binary(random_password(3)),

			UserExists = ejabberd_auth:is_user_exists(FormattedPhone,Server),

			if 
				(UserExists == true) ->
					ejabberd_auth:set_password(FormattedPhone,Server,NewPasswd),
					SmsUrl = ?SMS_BASE_URL ++ BinPhone ++ "&text=" ++ binary_to_list(NewPasswd),
					{ok, {{Version, 202, ReasonPhrase}, Headers, Body}} = httpc:request(SmsUrl),
					Jid = jlib:jid_to_string(#jid{user = FormattedPhone, server = Server}),
					jlib:iq_to_xml(IQ#iq{
						type = result,
					 	sub_el = [
						   #xmlel{
						      	name = <<"old-account">>, 
						      	attrs = [
							    	{<<"jid">>,Jid}
							    ] 
						     }
						  ]
					});
				true ->	 
					CheckPhone = mod_number_lookup:check_phone(FormattedPhone),
					[{ip,Ip},{iv,Iv},{mcc,Mcc},{mnc,Mnc}] = CheckPhone,
					if
						(Iv == true) ->
							{atomic, ok} = ejabberd_auth:try_register(FormattedPhone, Server, NewPasswd),
							SmsUrl = ?SMS_BASE_URL ++ BinPhone ++ "&text=" ++ binary_to_list(NewPasswd),
							{ok, {{Version, 202, ReasonPhrase}, Headers, Body}} = httpc:request(SmsUrl),
							ok = mnesia:dirty_write(#user_countries{user = FormattedPhone, country = list_to_binary(Mcc)}),
							Jid = jlib:jid_to_string(#jid{user = FormattedPhone, server = Server}),
							jlib:iq_to_xml(IQ#iq{
							 	type = result,
								sub_el = [
								   #xmlel{
								      	name = <<"new-account">>, 
								      	attrs = [
									       {<<"jid">>,Jid}
									    ] 
							     	}
						    	]
							});
						true ->
							jlib:iq_to_xml(IQ#iq{
								type = error,
							 	sub_el = [
								    #xmlel{
								      	name = <<"error">>, 
								      	attrs = [
									    	{<<"reason">>,<<"not valid phone number">>}
									    ] 
								    }
								]
							})
					end
			end;
		true -> 
			jlib:iq_to_xml(IQ#iq{type = error,sub_el = [SubEl, ?ERR_NOT_ALLOWED]})
	end;

unauthenticated_iq(Acc, _Server, _IQ, _IP) ->
	Acc.

