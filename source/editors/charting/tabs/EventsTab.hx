package editors.charting.tabs;

import editors.ChartingState;
import editors.ChartingState.UndoAction;

/**
	Builds the "Events" tab of the chart editor's main box: the event dropdown plus the add/remove and
	prev/next sub-event buttons and the two value inputs. Operates on the currently selected event note(s)
	through the editor. Reaches editor state/widgets via `@:access`.
**/
@:access(editors.ChartingState)
class EventsTab {
	/**
		Populates the Events tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the selected-event state
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Events').menu;
		var objX = 10;
		var objY = 25;

		s.eventDropDown = new PsychUIDropDownMenu(objX, objY, [], function(id:Int, character:String) {
			var eventSelected:Array<String> = s.eventsList[id];
			var eventName:String = eventSelected[0];
			var description:String = eventSelected[1];
			s.eventDescriptionText.text = description;
			if (s.selectedNotes.length > 1) {
				for (note in s.selectedNotes) {
					if (note == null || !note.isEvent)
						continue;

					note.events[note.events.length - 1][0] = eventName;
					note.updateEventText();
				}
			} else if (s.selectedNotes.length == 1 && s.selectedNotes[0].isEvent) {
				var event:ChartNote = s.selectedNotes[0];
				event.events[Std.int(FlxMath.bound(s.curEventSelected, 0, event.events.length - 1))][0] = eventName;
				event.updateEventText();
			}
		});

		function genericEventButton(func:ChartNote->Void) {
			if (s.selectedNotes.length == 1) {
				if (s.selectedNotes[0].isEvent) {
					func(s.selectedNotes[0]);
					s.updateSelectedEventText();
				} else
					s.showOutput('Note selected must be an Event!', true);
			} else
				s.showOutput('You must select a single event to press this button.', true);
		}

		var objX2 = 140;
		var removeButton:PsychUIButton = new PsychUIButton(objX2, objY, '-', function() {
			genericEventButton(function(event:ChartNote) {
				if (event.events.length > 1) {
					var selectedEvent = event.events[s.curEventSelected];
					if (selectedEvent != null) {
						event.events.remove(selectedEvent);
						event.updateEventText();
						s.curEventSelected--;
					} else
						s.showOutput('No event is selected when you deleted it?? Weird.', true);
				} else {
					s.selectedNotes.remove(event);
					s.events.remove(event);
					if (event.sprite != null)
						event.sprite.unbind(); // return the drawable to the pool
					s.addUndoAction(UndoAction.DELETE_NOTE, {events: [event]});
				}
			});
		}, 20);
		var addButton:PsychUIButton = new PsychUIButton(objX2 + 30, objY, '+', function() {
			genericEventButton(function(event:ChartNote) {
				event.events.push([
					s.eventsList[Std.int(Math.max(s.eventDropDown.selectedIndex, 0))][0],
					s.value1InputText.text,
					s.value2InputText.text
				]);
				event.updateEventText();
				s.curEventSelected++;
			});
		}, 20);
		var leftButton:PsychUIButton = new PsychUIButton(objX2 + 80, objY, '<', function() {
			genericEventButton(function(event:ChartNote) s.curEventSelected = FlxMath.wrap(s.curEventSelected - 1, 0, event.events.length - 1));
		}, 20);
		var rightButton:PsychUIButton = new PsychUIButton(objX2 + 110, objY, '>', function() {
			genericEventButton(function(event:ChartNote) s.curEventSelected = FlxMath.wrap(s.curEventSelected + 1, 0, event.events.length - 1));
		}, 20);
		removeButton.normalStyle.bgColor = FlxColor.RED;
		removeButton.normalStyle.textColor = FlxColor.WHITE;
		addButton.normalStyle.bgColor = FlxColor.GREEN;
		addButton.normalStyle.textColor = FlxColor.WHITE;

		s.selectedEventText = new FlxText(150, objY + 30, 150, '');
		s.selectedEventText.visible = false;

		function changeEventsValue(str:String, n:Int) {
			if (s.selectedNotes.length > 1) {
				for (note in s.selectedNotes) {
					if (note == null || !note.isEvent)
						continue;

					note.events[note.events.length - 1][n] = str;
					note.updateEventText();
				}
			} else if (s.selectedNotes.length == 1 && s.selectedNotes[0].isEvent) {
				var event:ChartNote = s.selectedNotes[0];
				event.events[Std.int(FlxMath.bound(s.curEventSelected, 0, event.events.length - 1))][n] = str;
				event.updateEventText();
			}
		}

		objY += 70;
		s.value1InputText = new PsychUIInputText(objX, objY, 120, '', 8);
		s.value1InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 1);
		s.value2InputText = new PsychUIInputText(objX + 150, objY, 120, '', 8);
		s.value2InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 2);

		objY += 40;
		s.eventDescriptionText = new FlxText(objX, objY, 280, ChartingState.defaultEvents[0][1]);

		tab_group.add(new FlxText(s.eventDropDown.x, s.eventDropDown.y - 15, 80, 'Event:'));
		tab_group.add(new FlxText(s.value1InputText.x, s.value1InputText.y - 15, 80, 'Value 1:'));
		tab_group.add(new FlxText(s.value2InputText.x, s.value2InputText.y - 15, 80, 'Value 2:'));

		tab_group.add(removeButton);
		tab_group.add(addButton);
		tab_group.add(leftButton);
		tab_group.add(rightButton);
		tab_group.add(s.selectedEventText);

		tab_group.add(s.value1InputText);
		tab_group.add(s.value2InputText);
		tab_group.add(s.eventDescriptionText);

		tab_group.add(s.eventDropDown); // lowest priority to display properly
	}
}
