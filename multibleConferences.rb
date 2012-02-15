require 'rubygems' 
require 'net/http' 
require 'json' 


#This is the HTTP request for CouchDB class 
module Couch 

  class Server 
    def initialize(host, port, options = nil) 
      @host = host 
      @port = port 
      @options = options 
    end 

    def delete(uri) 
      request(Net::HTTP::Delete.new(uri)) 
    end 

    def get(uri) 
      request(Net::HTTP::Get.new(uri)) 
    end 

    def put(uri, json) 
      req = Net::HTTP::Put.new(uri) 
      req["content-type"] = "application/json" 
      req.body = json 
      request(req) 
    end 

    def request(req) 
      res = Net::HTTP.start(@host, @port) { |http|http.request(req) } 
      unless res.kind_of?(Net::HTTPSuccess) 
        handle_error(req, res) 
      end 
      res 
    end 

    private 

    def handle_error(req, res) 
      e = RuntimeError.new("#{res.code}:#{res.message}\nMETHOD:#{req.method}\nURI:#{req.path}\n#{res.body}") 
      raise e 
    end 
  end 
end 

#This method say each conference and lets the user pick through it 
def determineRoom(conferenceRooms, looking) 

  say"Press the number according to the room you want to enter or zero to exit" 
  incr = 1 
  conferenceRooms.each { |x| 
    askRoom = ask "Press #{incr} for #{x}", { 
      :choices => "[1 DIGIT]", 
      :timeout => 2, 
      :mode => "dtmf", 
      :interdigitTimeout => 5 , 
      :onChoice => lambda { |event| 
        say "Thank you! You choice was accepted" 
        $choice = event.value 
        looking = "2" 
      },
      :onHangup => lambda { |event| 
        $choice = "0"
        looking = "2" 
      }
    }  
    break if looking == "2" 
    incr += 1 
  } 
  if looking == "1"
    say"You did not specify a room, please try again."
    determineRoom(conferenceRooms, looking) 
  end
  return  $choice 
end 

#This is a helper method to get data from  couchDB 
def getCounchDBData 
  url = URI.parse("http://con.iriscouch.com/_utils/") 
  server = Couch::Server.new(url.host, url.port) 
  res = server.get("/conferences/count") 
  json = res.body 
  json = JSON.parse(json) 
end 

#This updates the information when people are switching rooms 
def updateCouchDBData(roomNum, method, callerID) 
  
  json = getCounchDBData 
  url = URI.parse("http://couchgoodness.iriscouch.com/_utils/") 
  server = Couch::Server.new(url.host, url.port) 
  server.delete("/conferences") 
  server.put("/conferences", "") 
  avail = json["body"] 
  
  if method == "add" 
    avail["#{roomNum}"]["count"] = (avail["#{roomNum}"]["count"].to_i + 1).to_s 
    avail["#{roomNum}"]["people"][avail["#{roomNum}"]["people"].length] = "#{callerID}"
  else 
    avail["#{roomNum}"]["count"] = (avail["#{roomNum}"]["count"].to_i - 1).to_s
    incr = 0
    newPeople = []
    avail["#{roomNum}"]["people"].each do |x| 

      if x != callerID
        newPeople[incr]="#{x}"
        incr = incr + 1
      end
    end
    avail["#{roomNum}"]["people"] = newPeople
  end 


  doc = <<-JSON
  {"type":"comment","body": #{avail.to_json}}
  JSON

  server.put("/conferences/count", doc.strip) 
end 

#Different rooms available 
conferenceRooms = ["conference 1", "conference 2", "conference 3", "conference 4", "conference 5", "conference 6", "conference 7", "conference 8", "conference 9"]

#Determining which room to start with 
room = determineRoom(conferenceRooms, "1") 
room = room.to_i 
$choice = 1 
callerID = $currentCall.callerID
#This loop will be active until the user wants to leave all conferences 
while $choice != "0" 

  #Entering the specified conference 
  if $choice != "8" 
    #Promts the user which room they are entering and the options that they can choose from
    say"Entering room #{conferenceRooms[room.to_i - 1]}. Press 9 to move to the next room, 6 to move to the previous room, 8 to hear how many people are in the room, 1 to hear the choices again or 0 to exit." 
    #Updates the couchDB - takes the room number and goes to the function add and adds one person with their callerID
    updateCouchDBData(room.to_i, "add", callerID) 
  end 

  #Setting the choice to 0 in case of a hangup 
  $choice = "0" 
  
  #Entering the conference using the room number as the conference ID
  conference "#{room.to_i - 1}", { 
    :terminator => "6, 9, 0, 1, 8", 
    :mode => "dtmf", 
    :onChoice => lambda { |event| 
      #When the user hits eight, they want to stay in the room, but they want to know how many people are in the room
      if event.value != "8" 
        say("leaving room") 
      end 
      #setting the choice variable to the key pressed
      $choice = event.value    
    } 
  } 

  #Move to the next conference 
  if $choice == "9" 

    #This updates the database by subtracting 1 from the room count and removes the callerID
    updateCouchDBData(room.to_i, "sub", callerID) 
    #Since the user is moving to the next room, set the conference ID to the next room
    room = room.to_i + 1 
    #If the room number is greater than 9, set it back to the beginning
    if room.to_i > 9 
      room = "1" 
    end 

  #Move to the previous conference 
  elsif $choice == "6" 

    #This updates the database by subtracting 1 from the room count and removes the callerID
    updateCouchDBData(room.to_i, "sub", callerID) 
    #Since the user is moving to the previous room, set the conference ID to the room before
    room = room.to_i - 1 
    #If the room number is less than 1, set it to the last conference ID
    if room.to_i < 1 
      room = "9" 
    end 

  #Listing all of the conferences 
  elsif $choice == "1" 

    #Since this method will prompt the user which room they want to enter, they are no 
    #longer in their current conferenece so remove them
    updateCouchDBData(room.to_i, "sub", callerID) 
    #Use the method determineRoom to prompt the user
    room = determineRoom(conferenceRooms, "1") 
    #Set the conference ID
    room = room.to_i

  #Giving the number of people in that room 
  elsif $choice == "8" 
    json = getCounchDBData 
    count = json["body"]["#{room}"]["count"]
    say "There is #{count} in the room." 
    
  #This means the person hungup, so delete him from that room 
  elsif $choice == "0" 
    updateCouchDBData(room.to_i, "sub", callerID) 
  end 
  
end 
say"Please come back soon!"