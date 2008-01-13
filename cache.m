Cache : module
{
	PATH : con "/dis/sfgui/cache.dis";

	StrCache : adt
	{
		cache	: list of (string, string);

		new	: fn(): ref StrCache;
		insert	: fn(me: self ref StrCache, key, value: string);
		delete	: fn(me: self ref StrCache, key: string): list of string;
	};
};
