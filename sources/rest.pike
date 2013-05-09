inherit "classes/Script";
#include <database.h>
#include <classes.h>

mapping execute(mapping vars)
{
    werror("(WE WON'T REST %O)\n", vars->request);
    mapping result = ([]);
    object o;

    result->user = describe_object(this_user());
    result->__version = this()->get_object()->query_attribute("OBJ_SCRIPT")->query_attribute("DOC_VERSION");

    if (vars->__body)
    {
        vars->_json = vars->__body;
        vars->__data = Standards.JSON.decode(vars->__body);
        werror("(REST %O)\n(REST %O)\n", vars->__data, vars->__body);
    }

    if (this()->get_object()["handle_"+vars->request])
    {
        result += this()->get_object()["handle_"+vars->request](vars);
    }
    else if (!vars->request || vars->request == "/")
    {
        result->classes = describe_object(Array.filter(this_user()->get_groups(), GROUP("ekita")->is_virtual_member)[*]);
        result->all_schools = describe_object(GROUP("ekita")->get_sub_groups()[*]);
    }
    else if (vars->request[0] == '/')
    {
        o = _Server->get_module("filepath:url")->path_to_object(vars->request);
        result = describe_object(o, 1);
        if (o->get_object_class() & CLASS_CONTAINER)
            result->documents = describe_object(o->get_inventory()[*]);
        if (o->get_object_class() & CLASS_ROOM)
            this_user()->move(o);
    }
    else
    {
        o = GROUP(vars->request);
        if (o)
            result += handle_group(o, vars);
	else
	{
	    result->error = "request not found";
	    result->request = vars->request;
	}
    }

    return ([ "data":Standards.JSON.encode(result), "type":"application/json" ]);
}

mapping handle_group(object group, mapping vars)
{
    mixed err;
    mixed res;
    if (vars->__data && sizeof(vars->__data))
    {
	err = catch{ res = postgroup(group, vars->__data); };
    }

    mapping result = describe_object(group, 1);
    catch{ result->menu = describe_object(group->query_attribute("GROUP_WORKROOM")->get_inventory_by_class(CLASS_ROOM)[*]); };
    catch{ result->documents = describe_object(group->query_attribute("GROUP_WORKROOM")->get_inventory_by_class(CLASS_DOCHTML)[*], 1); };
    result->subgroups = describe_object(group->get_sub_groups()[*]);
    if (err)
       result->error = sprintf("%O", err[0]);
    if (objectp(res))
	result->res = describe_object(res);
    else if (res)
       result->res = sprintf("%O", res);
    return result;
}

mapping describe_object(object o, int|void show_details)
{
    function get_path = _Server->get_module("filepath:url")->object_to_filename;
    mapping desc = ([]);
    desc->oid = o->get_object_id();
    desc->path = get_path(o);
    desc->title = o->query_attribute("OBJ_DESC");
    desc->name = o->query_attribute("OBJ_NAME");

    if (o->get_class() == "User")
    {
        desc->id = o->get_identifier();
        desc->fullname = o->query_attribute("USER_FULLNAME");
        desc->path = get_path(o->query_attribute("USER_WORKROOM"));
        if (show_details)
            desc->trail = describe_object(Array.uniq(reverse(o->query_attribute("trail")))[*]);
    }

    if (o->get_class() == "Group")
    {
        object workroom = o->query_attribute("GROUP_WORKROOM");
        desc->id = o->get_identifier();
        desc->name = (o->get_identifier()/".")[-1];
        desc->path = get_path(workroom);
        if (show_details)
        {
            //object schedule = workroom->get_object_byname("schedule");
            //if (schedule)
            //    desc->schedule = schedule->get_content();
            desc->members = describe_object(o->get_members(CLASS_USER)[*]);
            if (o->get_parent())
                desc->parent = describe_object(o->get_parent());
	    if (o->query_attribute("event"))
		desc->event=o->query_attribute("event");
        }
    }

    if (o->get_object_class() & CLASS_DOCUMENT)
    {
        desc->mime_type = o->query_attribute("DOC_MIME_TYPE");
        if (show_details)
            catch { desc->content = o->get_content(); };
    }

    return desc;
}

string|object postgroup(object group, mapping post)
{
    werror("(REST postgroup) %O\n", post);
    if (post->newgroup)
        return "old API for creating groups is no longer supported";

    if (post->type && this()->get_object()["handle_group_"+post->type])
        return this()->get_object()["handle_group_"+post->type](group, post);
    else
        return handle_group_post(group, post);
}

string|object handle_group_post(object group, mapping post)
{
    if (post->action == "new")
    {
        if (!post->name)
            return "name missing!";
        
	object factory = _Server->get_factory(CLASS_GROUP);
	object child_group = factory->execute( ([ "name":post->name, "parentgroup":group ]) );
	if (post->title)
	    child_group->set_attribute("OBJ_DESC", post->title);
        return child_group;
    }
    else if (post->action == "update")
    {
        if (post->title)
	    group->set_attribute("OBJ_DESC", post->title);
        if (post->name) // rename group
            return "renaming groups not yet supported";        
        return group;
    }
    else
        return sprintf("action %s not supported", post->action);
}

string|object handle_group_event(object group, mapping post)
{
    group = handle_group_post(group, post);

    werror("(REST handling an event)\n");
    group->set_attribute("event", group->query_attribute("event")+post->event);
    return group;
}


void makeevent(object group, mapping data)
{
    werror("(REST making an event)\n");
    group->set_attribute("event", data);
}


mapping handle_login(mapping vars)
{
    mapping result =([]);
    if (vars->request == "login")
    {
        if (this_user() != USER("guest"))
            result->login = "login successful";
        else
            result->login = "user not logged in";
    }
    return result;
}

mapping handle_settings(mapping vars)
{
    mapping result =([]);
    if (vars->request == "settings")
    {
        if (vars->__data && sizeof(vars->__data))
            foreach (vars->__data; string key; string value)
            {
                if (this_user()->query_attribute(key) != value)
                    this_user()->set_attribute(key, value);
            }
        result->settings = this_user()->query_attributes() & (< "OBJ_DESC", "OBJ_NAME", "USER_ADRESS", "USER_EMAIL", "USER_FIRSTNAME", "USER_FULLNAME", "USER_LANGUAGE" >);
    }
    return result;
}

mapping handle_register(mapping vars)
{
    werror("REST: register\n");
    mapping result = ([]);
    result->error = "register not supported yet";
    result->data = vars;
    return result;
}
