#--
# Cloud Foundry 2012.02.03 Beta
# Copyright (c) [2009-2012] VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache License, Version 2.0 (the "License").
# You may not use this product except in compliance with the License.
#
# This product includes a number of subcomponents with
# separate copyright notices and license terms. Your use of these
# subcomponents is subject to the terms and conditions of the
# subcomponent's license, as noted in the LICENSE file.
#++

require 'uaa/http'

module CF::UAA

# This class is for apps that need to manage User Accounts, Groups, or OAuth Client Registrations.
# It provides access to the SCIM endpoints on the UAA.
class Scim

  include Http

  private

  def force_attr(k)
    kd = k.to_s.downcase
    kc = {"username" => "userName", "familyname" => "familyName", 
      "givenname" => "givenName", "middlename" => "middleName", 
      "honorificprefix" => "honorificPrefix", 
      "honorificsuffix" => "honorificSuffix", "displayname" => "displayName",
      "nickname" => "nickName", "profileurl" => "profileUrl",
      "streetaddress" => "streetAddress", "postalcode" => "postalCode",
      "usertype" => "userType", "preferredlanguage" => "preferredLanguage",
      "x509certificates" => "x509Certificates", "lastmodified" => "lastModified",
      "externalid" => "externalId", "phonenumbers" => "phoneNumbers",
      "startindex" => "startIndex"}[kd]
    kc || kd
  end

  # This is very inefficient and should be unnecessary. SCIM (1.1 and early
  # 2.0 drafts) specify that attribute names are case insensitive. However
  # in the UAA attribute names are currently case sensitive. This hack takes
  # a hash with keys as symbols of strings and with any case, and forces
  # the attribute name to the case that the uaa expects.
  def force_case(obj)
    return obj.collect {|o| force_case(o)} if obj.is_a? Array
    return obj unless obj.is_a? Hash
    obj.each_with_object({}) {|(k, v), h| h[force_attr(k)] = force_case(v) }
  end

  def prep_request(type, info = nil)
    unless path = {user: "/Users", group: "/Groups", client: "/oauth/clients", 
        user_id: "/ids/Users"}[type]
      raise ArgumentError, "scim resource type must be :user, :group, :client, :user_id"
    end
    [path, force_case(info)]
  end

  public

  # the auth_header parameter refers to a string that can be used in an
  # authorization header. For oauth with jwt tokens this would be something
  # like "bearer xxxx.xxxx.xxxx". The Token class returned by TokenIssuer
  # provides an auth_header method for this purpose.
  def initialize(target, auth_header) @target, @auth_header = target, auth_header end

  # info is a hash structure converted to json and sent to the scim /Users endpoint
  def add(type, info)
    path, info = prep_request(type, info)
    reply = json_parse_reply(*json_post(@target, path, info, @auth_header), :down)
    return reply if reply && reply["id"]
    raise BadResponse, "no id returned by add request to #{@target}#{path}"
  end

  # info is a hash structure converted to json and sent to the scim /Users endpoint
  def put(type, id, info)
    path, info = prep_request(type, info)
    hdrs = info && info["meta"] && info["meta"]["version"] ? 
        {'if-match' => info["meta"]["version"]} : {}
    json_parse_reply(*json_put(@target, "#{path}/#{URI.encode(id)}", info,
        @auth_header, hdrs), :down)
  end

  # TODO: fix this when the UAA supports patch
  # info is a hash structure converted to json and sent to the scim /Users endpoint
  #def patch(path, id, info, attributes_to_delete = nil)
  #  info = info.merge(meta: { attributes: Util.arglist(attributes_to_delete) }) if attributes_to_delete
  #  json_parse_reply(*json_patch(@target, "#{path}/#{URI.encode(id)}", info, @auth_header))
  #end

  # supported query keys are: attributes, filter, startIndex, count
  # output hash keys are: resources, totalResults, itemsPerPage
  def query(type, query = {})
    path, query = prep_request(type, query)
    query = query.reject {|k, v| v.nil? }
    if attrs = query['attributes']
      query['attributes'] = Util.strlist(Util.arglist(attrs), ",")
    end
    qstr = query.empty?? '': "?#{URI.encode_www_form(query)}"
    info = json_get(@target, "#{path}#{qstr}", @auth_header, :down)
    unless info.is_a?(Hash) && info['resources'].is_a?(Array)
      raise BadResponse, "invalid reply to query of #{@target}#{path}"
    end
    info
  end

  def get(type, id) 
    path, _ = prep_request(type)
    json_get(@target, "#{path}/#{URI.encode(id)}", @auth_header, :down)
  end

  # collects all pages of entries from a query, returns array of results.
  # Type can be any scim resource type
  def all_pages(type, query = {})
    query = query.reject {|k, v| v.nil? }
    query["startindex"], info = 1, []
    while true
      qinfo = query(type, query)
      return info unless qinfo["resources"] && !qinfo["resources"].empty?
      info.concat(qinfo["resources"])
      return info unless qinfo["totalresults"] && qinfo["totalresults"] > info.length
      unless qinfo["startindex"] && qinfo["itemsperpage"]
        raise BadResponse, "incomplete pagination data from #{@target}#{path}"
      end
      query["startindex"] = info.length + 1
    end
  end

  def change_password(user_id, new_password, old_password = nil)
    password_request = {"password" => new_password}
    password_request["oldPassword"] = old_password if old_password
    json_parse_reply(*json_put(@target, "/Users/#{URI.encode(user_id)}/password", password_request, @auth_header))
  end

  def change_secret(client_id, new_secret, old_secret = nil)
    req = {"secret" => new_secret }
    req["oldSecret"] = old_secret if old_secret
    json_parse_reply(*json_put(@target, "/oauth/clients/#{URI.encode(client_id)}/secret", req, @auth_header))
  end

end

end
