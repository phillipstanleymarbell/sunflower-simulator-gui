implement Cache;

include "cache.m";

StrCache.new(): ref StrCache
{
	return ref StrCache(nil);
}

StrCache.insert(me: self ref StrCache, key, value: string)
{
	me.cache = (key, value) :: me.cache;
}

StrCache.delete(me: self ref StrCache, key: string): list of string
{
	retlist : list of string;
	tmplist : list of (string, string);

	while (me.cache != nil)
	{
		(k, v) := hd me.cache;
		if (k != key)
		{
			tmplist = (k, v) :: tmplist;
		}
		else
		{
			retlist = v :: retlist;
		}
		me.cache = tl me.cache;
	}
	me.cache = tmplist;

	return retlist;
}
