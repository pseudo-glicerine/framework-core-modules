local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(ReplicatedStorage.Packages.Promise)

local PREFIX = "[EventBus]: "

local EventBus = {
	Subscribers = {} :: { [SubscriberName]: SubscriberData },
}
type EventBus = typeof(EventBus)

type Event = string
type Callback = (...any) -> ()

type SubscriberName = string
type SubscriberData = {
	[Event]: Callback,
}

export type EmitPromise = typeof(Promise.new(...))
export type Subscription = typeof(table.freeze({} :: {
	Unsubscribe: (self: Subscription) -> (),
}))

local function log(msg: string)
	local debuggingEnabled = script:GetAttribute("Debugging")

	if debuggingEnabled then
		print(PREFIX, msg)
	end
end

-- // Emits an event to all its subscribers
function EventBus.Emit(self: EventBus, event: string, ...): EmitPromise
	local args = { ... }
	local promises = {}
	for subscriber, subscriberData in self.Subscribers do
		if type(subscriberData[event]) == "function" then
			local promise = Promise.new(function(resolve, reject)
				local success = pcall(subscriberData[event], table.unpack(args))
				if success then
					resolve()
				else
					reject(subscriber)
				end
			end):catch(function()
				log(`An error occurred while invoking {subscriber}'s callback for event "{event}"`)
			end)

			table.insert(promises, promise)
		end
	end

	return Promise.all(promises):finally(function()
		log(`All subscriber callbacks for event "{event}" were successfully executed with the provided data`)
	end)
end

-- // Subscribes to an event
function EventBus.Subscribe(self: EventBus, sbName: string, event: string, callback: (...any) -> ...any): Subscription
	if not self.Subscribers[sbName] then
		self.Subscribers[sbName] = {}
	end

	self.Subscribers[sbName][event] = callback

	return table.freeze({
		Unsubscribe = function(_)
			self:Unsubscribe(sbName, event)
		end :: () -> nil,
	})
end

-- // Unsubscribes from an event
function EventBus.Unsubscribe(self: EventBus, sbName: string, event: string)
	if not self.Subscribers[sbName] then
		return
	end

	self.Subscribers[sbName][event] = nil
end

-- // Unsubscribes each subscriber from an event
function EventBus.UnsubscribeAll(self: EventBus, event: string)
	for subscriber, subscriberData in self.Subscribers do
		if subscriberData[event] then
			self.Subscribers[subscriber][event] = nil
		end
	end
end

return EventBus
