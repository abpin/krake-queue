kson = require 'kson'
# @Description: This class handles the interfacing between the scraping system and the redis server
redis = require 'redis'
fs = require 'fs'

class QueueInterface

  # @Description: Default constructor
  # @param: redisInfo:object
  #   - host:string
  #   - port:string
  #   - masterList:string
  #   - queueName:string
  #   - scrapeMode:string
  #       depth | breadth
  #         depth = go as deep as possible before going beadth
  #       breadth
  #         breadth = go as broad as possiblebefore going deep  
  # @param: initialCallBack:function()
  constructor: (redisInfo, initialCallBack)->
    @eventListeners = {}
    
    #when true prevents pushing to queue stack
    @stop_send = false 
    
    #when true no longer listens for any messages
    @stop_receive = false
    
    @redisInfo = redisInfo
    @redisClient = redis.createClient redisInfo.port, redisInfo.host
    @redisEventListener = redis.createClient redisInfo.port, redisInfo.host
    
    console.log "[QUEUE_INTERFACE] : Subscribed to : " + redisInfo.queueName + "*"
    @redisEventListener.psubscribe (redisInfo.queueName + "*")
      
    @redisEventListener.on 'pmessage', (channel_name , event_key, message)=>
      if @stop_receive then return
      event_name = event_key.split(':')[1]
      queueName = event_key.split(':')[0]
      try resObj = kson.parse message
      catch e then resObj = {}
      @eventListeners[event_name] && @eventListeners[event_name](queueName, resObj)

    initialCallBack && initialCallBack()


  
  # @Description: sets the event listeners, triggered with event is called remotely
  # @param: event_key:string
  # @param: callback:function()
  setEventListener: (event_key, callback)->
    @eventListeners[event_key] = callback


  # @Description: broadcast an event to all slaves and master in the cluster
  # @param: authToken:string
  # @param: eventName:string
  # @param: message:string
  # @param: callback:function()
  broadcast: (authToken, eventName, message, callback)->
    message = kson.stringify message
    switch eventName
      when 'mercy', 'status ping', 'new task', 'logs', 'results', 'kill task'
        @redisClient.publish authToken + ':' + eventName, message, (error, result)=>
          callback && callback()
      else
        console.log '[QUEUE_INTERFACE] unrecognized event : %s ', eventName



  # @Description: gets count of outstanding subtask for task
  # @param: queueName:string
  # @param: callback:function(result:integer)
  getNumTaskleft: (queueName, callback)->
    @redisClient.llen queueName, (error, result)=>
      callback result



  # @Description: gets the next task from the queue
  # @param: queueName:string
  # @param: callback:function( task_option_obj:object || false:boolean )
  #    E.g. task_option_obj
  #      options = 
  #        origin_url : 'http://www.mdscollections.com/cat_mds_accessories17.cfm'
  #        columns : [{
  #            col_name : 'title'
  #            dom_query : '.listing_product_name' 
  #          }, { 
  #            col_name : 'price'
  #            dom_query : '.listing_price' 
  #           }, { 
  #            col_name : 'detailed_page_href'
  #            dom_query : '.listing_product_name'
  #            required_attribute : 'href'
  #         }]
  #        next_page :
  #          dom_query : '.listing_next_page'
  #        detailed_page :
  #          columns : [{
  #            col_name : 'description'
  #            dom_query : '.tabfield18504'
  #          }]   
  getTaskFromQueue: (queueName, callback)->
    
    switch @redisInfo.scrapeMode
      when 'depth' then pop_method = 'rpop'
      when 'breadth' then pop_method = 'lpop'
      else pop_method = 'lpop'
      
    @redisClient[pop_method] queueName, (error, task_info_string)=>
      try
        if task_info_string
          task_option_obj = kson.parse task_info_string
          callback task_option_obj
        else 
          callback false          
      catch error
        callback false



  # @Description: adds a new task to the end of queue
  # @param: queueName:string
  # @param: task_type:string
  #    - There are only 2 task_types to date :
  #       'listing page scrape'
  #       'detailed page scrape'  
  # @param: task_option_obj:object
  # @param: task_position:string
  # @param: callback:function()
  addTaskToQueue: (queueName, task_type, task_option_obj, task_position, callback)->

    if @stop_send
      console.log '[QUEUE_INTERFACE] : Embargoed. Not pushing anything to the queue stack'
      return

    switch task_position
      when 'head' then pushMethod = 'lpush'
      when 'tail' then pushMethod = 'rpush'
      when 'bad' then pushMethod = 'rpush'  
      else pushMethod = 'rpush'

    if task_position == 'bad' then queueName == 'QUARANTINED_TASKS'

    task_option_obj.task_id = queueName
    task_option_obj.task_type = task_type
    task_info_string = kson.stringify task_option_obj
    @redisClient[pushMethod] queueName, task_info_string, (error, result)=>
      callback && callback()


  
  # @Description: empties the task queue
  # @param: queueName:string
  # @param: callback:function()  
  emptyQueue : (queueName, callback)->
    @redisClient.del queueName, (error, result)=>
      console.log '[QUEUE_INTERFACE] : Task Queue (%s) was emptied', queueName      
      callback && callback()
  


module.exports = QueueInterface