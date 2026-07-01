package editors.charting.tabs;

import haxe.Json;
import haxe.Exception;
import backend.Song;
import editors.charting.VSlice;
import editors.content.Prompt;
import editors.content.PsychJsonPrinter;
import editors.ChartingState;

/**
	Builds the "File" toolbar menu of the chart editor: new/open/autosave/events, save variants, reload,
	the V-Slice import/export and legacy-format updater, plus preview/playtest/exit. All file I/O and
	conversion routes through the editor. Reaches editor state/dialogs via `@:access`.
**/
@:access(editors.ChartingState)
class FileTab {
	/**
		Populates the File toolbar menu in `s.upperBox`.
		@param s the chart editor that owns the toolbar, file dialog and save/convert hooks
	**/
	public static function build(s:ChartingState):Void {
		var tab = s.upperBox.getTab('File');
		var tab_group = tab.menu;
		var btnX = tab.x - s.upperBox.x;
		var btnY = 1;
		var btnWid = Std.int(tab.width);

		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  New', function() {
			var func:Void->Void = function() {
				s.openNewChart();
				s.reloadNotesDropdowns();
				s.prepareReload();
			}

			if (!s.ignoreProgressCheckBox.checked)
				s.openSubState(new Prompt('Are you sure you want to start over?', func));
			else
				func();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Open Chart...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.fileDialog.open(function() {
				try {
					var filePath:String = s.fileDialog.path.replace('\\', '/');
					var loadedChart:SwagSong = Song.parseJSON(s.fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
					if (loadedChart == null || !Reflect.hasField(loadedChart, 'song')) // Check if chart is ACTUALLY a chart and valid
					{
						s.showOutput('Error: File loaded is not a Psych Engine/FNF 0.2.x.x chart.', true);
						return;
					}

					var func:Void->Void = function() {
						s.loadChart(loadedChart);
						Song.chartPath = s.fileDialog.path;
						s.reloadNotesDropdowns();
						s.prepareReload();
						s.showOutput('Opened chart "${Song.chartPath}" successfully!');
					}

					if (!s.ignoreProgressCheckBox.checked)
						s.openSubState(new Prompt('Warning: Any unsaved progress\nwill be lost.', func));
					else
						func();
				} catch (e:Exception) {
					s.showOutput('Error: ${e.message}', true);
					trace(e.stack);
				}
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Open Autosave...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			if (!FileSystem.exists('backups/')) {
				s.showOutput('The "backups" folder does not exist.', true);
				return;
			}

			var fileList:Array<String> = FileSystem.readDirectory('backups/').filter((file:String) -> file.endsWith('.${s.BACKUP_EXT}'));
			if (fileList.length < 1) {
				s.showOutput('No autosave files found.', true);
				return;
			}

			fileList.sort((a:String, b:String) -> (a.toUpperCase() < b.toUpperCase()) ? 1 : -1); // Sort alphabetically descending
			var maxItems:Int = Std.int(Math.min(5, fileList.length));
			var radioGrp:PsychUIRadioGroup = new PsychUIRadioGroup(0, 0, fileList, 25, maxItems, false, 240);
			radioGrp.checked = 0;

			var hei:Float = radioGrp.height + 160;
			s.openSubState(new BasePrompt(420, hei, 'Choose an Autosave', function(state:BasePrompt) {
				s.upperBox.isMinimized = true;
				s.upperBox.bg.visible = false;

				var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
				btn.cameras = state.cameras;
				state.add(btn);

				radioGrp.screenCenter(X);
				radioGrp.y = state.bg.y + 80;
				radioGrp.cameras = state.cameras;
				state.add(radioGrp);

				var btn:PsychUIButton = new PsychUIButton(0, radioGrp.y + radioGrp.height + 20, 'Load', function() {
					var autosaveName:String = fileList[radioGrp.checked];
					var path:String = 'backups/$autosaveName';
					state.close();

					if (FileSystem.exists(path)) {
						try {
							var loadedChart:SwagSong = Song.parseJSON(File.getContent(path), autosaveName, null);
							if (loadedChart == null || !Reflect.hasField(loadedChart, '__original_path')) {
								s.showOutput('Error: File loaded is not a valid Psych Engine autosave.', true);
								return;
							}

							var originalPath:String = Reflect.field(loadedChart, '__original_path');
							Reflect.deleteField(loadedChart, '__original_path');

							var func:Void->Void = function() {
								Song.chartPath = FileSystem.exists(originalPath) ? originalPath : null;
								s.loadChart(loadedChart);
								s.reloadNotesDropdowns();
								s.prepareReload();

								s.showOutput('Opened autosave "$autosaveName" successfully!');
							}

							if (!s.ignoreProgressCheckBox.checked)
								s.openSubState(new Prompt('Warning: Any unsaved progress\nwill be lost.', func));
							else
								func();
						} catch (e:Exception) {
							s.showOutput('Error on loading autosave: ${e.message}', true);
						}
					} else
						s.showOutput('Error! Autosave file selected could not be found, huh??', true);
				});
				btn.cameras = state.cameras;
				btn.screenCenter(X);
				state.add(btn);
			}));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if (ChartingState.SHOW_EVENT_COLUMN) {
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Open Events...', function() {
				if (!s.fileDialog.completed)
					return;
				s.upperBox.isMinimized = true;
				s.upperBox.bg.visible = false;

				s.fileDialog.open(function() {
					try {
						var filePath:String = s.fileDialog.path.replace('\\', '/');
						var eventsFile:SwagSong = Song.parseJSON(s.fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
						if (eventsFile == null || Reflect.hasField(eventsFile, 'scrollSpeed') || eventsFile.events == null) {
							s.showOutput('Error: File loaded is not a Psych Engine chart/events file.', true);
							return;
						}

						var loadedEvents:Array<Dynamic> = eventsFile.events;
						if (loadedEvents.length < 1) {
							s.showOutput('Events file loaded is empty.', true);
							return;
						}

						s.openSubState(new BasePrompt('Events Found! Choose an action.', function(state:BasePrompt) {
							var btnY = 390;
							var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Replace All', function() {
								for (event in s.events) {
									if (event != null) {
										event.destroy();
										s.selectedNotes.remove(event);
									}
								}
								s.undoStack.clear();
								s.events = [];

								for (event in loadedEvents)
									s.events.push(s.createEvent(event));

								s.softReloadNotes();
								state.close();
								s.showOutput('Events loaded successfully!');
							});
							btn.normalStyle.bgColor = FlxColor.RED;
							btn.normalStyle.textColor = FlxColor.WHITE;
							btn.screenCenter(X);
							btn.x -= 125;
							btn.cameras = state.cameras;
							state.add(btn);

							var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Add', function() {
								for (event in loadedEvents)
									s.events.push(s.createEvent(event));

								s.softReloadNotes();
								state.close();
								s.showOutput('Events added successfully!');
							});
							btn.screenCenter(X);
							btn.cameras = state.cameras;
							state.add(btn);

							var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Cancel', state.close);
							btn.screenCenter(X);
							btn.x += 125;
							btn.cameras = state.cameras;
							state.add(btn);
						}));
					} catch (e:Exception) {
						s.showOutput('Error: ${e.message}', true);
						trace(e.stack);
					}
				});
			}, btnWid);
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Save', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.saveChart();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Save as...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.saveChart(false);
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Save as psych_v2...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.saveChartV2();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if (ChartingState.SHOW_EVENT_COLUMN) {
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Save Events...', function() {
				if (!s.fileDialog.completed)
					return;
				s.upperBox.isMinimized = true;

				s.updateChartData();
				s.fileDialog.save('events.json', PsychJsonPrinter.print({events: PlayState.SONG.events, format: 'psych_v1'}, ['events']),
					function() s.showOutput('Events saved successfully to: ${s.fileDialog.path}'), null, function() s.showOutput('Error on saving events!', true));
			}, btnWid);
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Reload Chart', function() {
			var func:Void->Void = function() {
				if (Song.chartPath == null) {
					s.showOutput('You must save/load a Chart first to Reload it!', true);
					return;
				}

				if (FileSystem.exists(Song.chartPath)) {
					try {
						var reloadedChart:SwagSong = Song.parseJSON(File.getContent(Song.chartPath));
						s.loadChart(reloadedChart);
						s.reloadNotesDropdowns();
						s.prepareReload();
						s.showOutput('Chart reloaded successfully!');
					} catch (e:Exception) {
						s.showOutput('Error: ${e.message}', true);
						trace(e.stack);
					}
				} else
					s.showOutput('You must save/load a Chart first to Reload it!', true);
			}

			if (!s.ignoreProgressCheckBox.checked)
				s.openSubState(new Prompt('Warning: Any unsaved progress will be lost', func));
			else
				func();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Save (V-Slice)...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.fileDialog.openDirectory('Save V-Slice Chart/Metadata JSONs', function() {
				try {
					var path:String = s.fileDialog.path.replace('\\', '/');

					var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
					chartName = chartName.substring(chartName.lastIndexOf('/') + 1, chartName.lastIndexOf('.'));

					var chartFile:String = '$path/$chartName-chart.json';
					var metadataFile:String = '$path/$chartName-metadata.json';

					s.updateChartData();
					var pack:VSlicePackage = VSlice.export(PlayState.SONG);

					ClientPrefs.toggleVolumeKeys(false);
					s.openSubState(new BasePrompt('Metadata', function(state:BasePrompt) {
						var btnX = 640;
						var btnY = 400;
						var btn:PsychUIButton = new PsychUIButton(btnX, btnY, 'Save', function() {
							s.overwriteSavedSomething = false;
							s.overwriteCheck(chartFile, '$chartName-chart.json', PsychJsonPrinter.print(pack.chart, ['events', 'notes', 'scrollSpeed']),
								function() {
									s.overwriteCheck(metadataFile, '$chartName-metadata.json',
										PsychJsonPrinter.print(pack.metadata, ['characters', 'difficulties', 'timeChanges']), function() {
											if (s.overwriteSavedSomething)
												s.showOutput('Files saved successfully to: $path!');
									});
								});
							state.close();
						});
						btn.normalStyle.bgColor = FlxColor.GREEN;
						btn.normalStyle.textColor = FlxColor.WHITE;
						btn.cameras = state.cameras;
						state.add(btn);

						var btn:PsychUIButton = new PsychUIButton(btnX + 100, btnY, 'Cancel', state.close);
						btn.cameras = state.cameras;
						state.add(btn);

						var textX = FlxG.width / 2 - 155;
						var textY = 360;
						var artistInput:PsychUIInputText = new PsychUIInputText(textX, textY, 120, pack.metadata.artist, 8);
						artistInput.cameras = state.cameras;
						artistInput.onChange = function(old:String, cur:String) pack.metadata.artist = cur;

						var charterInput:PsychUIInputText = new PsychUIInputText(textX + 190, textY, 120, pack.metadata.charter, 8);
						charterInput.cameras = state.cameras;
						charterInput.onChange = function(old:String, cur:String) pack.metadata.charter = cur;

						var artistTxt:FlxText = new FlxText(artistInput.x, artistInput.y - 15, 100, 'Artist/Composer:');
						artistTxt.cameras = state.cameras;
						var charterTxt:FlxText = new FlxText(charterInput.x, charterInput.y - 15, 100, 'Charter:');
						charterTxt.cameras = state.cameras;
						state.add(artistTxt);
						state.add(charterTxt);
						state.add(artistInput);
						state.add(charterInput);
					}));

					// trace(pack.chart);
					// trace(pack.metadata);
					// trace(chartName, chartFile, metadataFile);
				} catch (e:Exception) {
					s.showOutput('Error: ${e.message}', true);
					trace(e.stack);
				}
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Psych to V-Slice...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.fileDialog.open('song.json', 'Open a Psych Engine Chart JSON', function() {
				var filePath:String = s.fileDialog.path.replace('\\', '/');
				var loadedChart:SwagSong = Song.parseJSON(s.fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
				if (loadedChart == null || !Reflect.hasField(loadedChart, 'song')) // Check if chart is ACTUALLY a chart and valid
				{
					s.showOutput('Error: File loaded is not a Psych Engine 0.x.x/FNF 0.2.x.x chart.', true);
					return;
				}

				var pack:VSlicePackage = VSlice.export(loadedChart);
				if (pack.chart == null || pack.metadata == null) {
					s.showOutput('Error: Chart loaded is invalid.', true);
					return;
				}

				ClientPrefs.toggleVolumeKeys(false);
				s.openSubState(new BasePrompt('Metadata', function(state:BasePrompt) {
					var songName:String = Paths.formatToSongPath(pack.metadata.songName);
					var parentFolder:String = filePath.substring(0, filePath.lastIndexOf('/') + 1);
					var artistInput, charterInput, difficultiesInput:PsychUIInputText = null;

					var btnX = 640;
					var btnY = 400;
					var btn:PsychUIButton = new PsychUIButton(btnX, btnY, 'Save', function() {
						try {
							var diffs:Array<String> = pack.metadata.playData.difficulties;
							if (diffs != null && diffs.length > 0) {
								var diffsFound:Array<String> = [];
								var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault());
								for (diff in diffs) {
									var diffPostfix:String = (diff != defaultDiff) ? '-$diff' : '';
									var chartToFind:String = parentFolder + songName + diffPostfix + '.json';
									if (FileSystem.exists(chartToFind)) {
										var diffChart:SwagSong = Song.parseJSON(File.getContent(chartToFind), songName + diffPostfix);
										if (diffChart != null) {
											var subpack:VSlicePackage = VSlice.export(diffChart);
											var diffSpeed:Null<Float> = subpack.chart.scrollSpeed.get(diff);
											var diffNotes:Array<VSliceNote> = subpack.chart.notes.get(diff);
											if (diffSpeed != null && diffNotes != null) {
												pack.chart.scrollSpeed.set(diff, diffSpeed);
												pack.chart.notes.set(diff, diffNotes);
											}
											// trace(diff, diffSpeed, diffNotes.length);
										}
									} else
										trace('File not found: $chartToFind');
								}

								var chartToFind:String = parentFolder + 'events.json';
								if (FileSystem.exists(chartToFind)) {
									var eventsChart:SwagSong = Song.parseJSON(File.getContent(chartToFind), 'events');
									if (eventsChart != null) {
										var subpack:VSlicePackage = VSlice.export(eventsChart);
										if (subpack.chart.events != null && subpack.chart.events.length > 0) {
											for (event in subpack.chart.events) {
												if (event == null)
													continue;
												pack.chart.events.push(event);
											}
										}
										@:privateAccess pack.chart.events.sort(VSlice.sortByTime);
									}
								}

								s.fileDialog.openDirectory('Save V-Slice Chart/Metadata JSONs', function() {
									s.overwriteSavedSomething = false;
									var path:String = s.fileDialog.path.replace('\\', '/');
									if (path.endsWith('/'))
										path = path.substr(0, path.length - 1);
									s.overwriteCheck('$path/$songName-chart.json', '$songName-chart.json',
										PsychJsonPrinter.print(pack.chart, ['events', 'notes', 'scrollSpeed']), function() {
											s.overwriteCheck('$path/$songName-metadata.json', '$songName-metadata.json',
												PsychJsonPrinter.print(pack.metadata, ['characters', 'difficulties', 'timeChanges']), function() {
													if (s.overwriteSavedSomething)
														s.showOutput('Files saved successfully to: $path!');
											});
									});
								});
							} else
								s.showOutput('Error: You need atleast one difficulty to export.', true);
						} catch (e:Exception) {
							s.showOutput('Error: ${e.message}', true);
							trace(e.stack);
						}
						state.close();
					});
					btn.normalStyle.bgColor = FlxColor.GREEN;
					btn.normalStyle.textColor = FlxColor.WHITE;
					btn.cameras = state.cameras;
					state.add(btn);

					var btn:PsychUIButton = new PsychUIButton(btnX + 100, btnY, 'Cancel', state.close);
					btn.cameras = state.cameras;
					state.add(btn);

					var textX = FlxG.width / 2 - 180;
					var textY = 360;
					artistInput = new PsychUIInputText(textX, textY, 120, pack.metadata.artist, 8);
					artistInput.cameras = state.cameras;
					artistInput.onChange = function(old:String, cur:String) pack.metadata.artist = cur;

					charterInput = new PsychUIInputText(textX + 150, textY, 120, pack.metadata.charter, 8);
					charterInput.cameras = state.cameras;
					charterInput.onChange = function(old:String, cur:String) pack.metadata.charter = cur;

					var diffs:Array<String> = pack.metadata.playData.difficulties;
					if (diffs == null || diffs.length < 0)
						pack.metadata.playData.difficulties = diffs = ['easy', 'normal', 'hard'];
					difficultiesInput = new PsychUIInputText(textX, textY + 42, 160, diffs.join(', '), 8);
					difficultiesInput.cameras = state.cameras;
					difficultiesInput.forceCase = LOWER_CASE;
					difficultiesInput.onChange = function(old:String, cur:String) {
						pack.metadata.playData.difficulties = cur.split(',');

						var diffs:Array<String> = pack.metadata.playData.difficulties;
						for (num => diff in diffs)
							diffs[num] = Paths.formatToSongPath(diff);

						while (diffs.contains('')) // Clear invalids cuz people might be stupid
							diffs.remove('');
					}

					var artistTxt:FlxText = new FlxText(artistInput.x, artistInput.y - 15, 100, 'Artist/Composer:');
					artistTxt.cameras = state.cameras;
					var charterTxt:FlxText = new FlxText(charterInput.x, charterInput.y - 15, 100, 'Charter:');
					charterTxt.cameras = state.cameras;
					var difficultiesTxt:FlxText = new FlxText(difficultiesInput.x, difficultiesInput.y - 15, 100, 'Difficulties:');
					difficultiesTxt.cameras = state.cameras;
					state.add(artistTxt);
					state.add(charterTxt);
					state.add(difficultiesTxt);
					state.add(artistInput);
					state.add(charterInput);
					state.add(difficultiesInput);
				}));
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  V-Slice to Psych...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.fileDialog.open('chart.json', 'Open a V-Slice Chart file', function() {
				var chart:VSliceChart = cast Json.parse(s.fileDialog.data);
				if (chart == null || chart.version == null || chart.notes == null || chart.scrollSpeed == null) {
					s.showOutput('Error: File loaded is not a valid FNF V-Slice chart.', true);
					return;
				}

				s.fileDialog.open('metadata.json', 'Open a V-Slice Metadata file', function() {
					var metadata:VSliceMetadata = cast Json.parse(s.fileDialog.data);
					if (metadata == null
						|| metadata.version == null
						|| metadata.playData == null
						|| metadata.songName == null
						|| metadata.playData.difficulties == null
						|| metadata.timeChanges == null
						|| metadata.timeChanges.length < 1) {
						s.showOutput('Error: File loaded is not a valid FNF V-Slice metadata.', true);
						return;
					}

					try {
						var pack:PsychPackage = VSlice.convertToPsych(chart, metadata);
						if (pack.difficulties != null) {
							s.fileDialog.openDirectory('Save Converted Psych JSONs', function() {
								var path:String = s.fileDialog.path.replace('\\', '/');
								if (!path.endsWith('/'))
									path += '/';

								var diffs:Array<String> = metadata.playData.difficulties.copy();
								var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault());
								function nextChart() {
									while (diffs.length > 0) {
										var diffName:String = diffs[0];
										diffs.remove(diffName);
										if (!pack.difficulties.exists(diffName))
											continue;

										var diffPostfix:String = (diffName != defaultDiff) ? '-$diffName' : '';
										var chartData:SwagSong = pack.difficulties.get(diffName);
										var chartName:String = Paths.formatToSongPath(chartData.song) + diffPostfix + '.json';
										s.overwriteCheck(path + chartName, chartName, PsychJsonPrinter.print(chartData, ['sectionNotes', 'events']), nextChart,
											true);
										return;
									}

									if (pack.events != null) {
										s.overwriteCheck(path + 'events.json', 'events.json', PsychJsonPrinter.print(pack.events, ['events']), function() {
											if (s.overwriteSavedSomething)
												s.showOutput('Files saved successfully to: ${s.fileDialog.path}!');
										}, true);
									} else if (s.overwriteSavedSomething)
										s.showOutput('Files saved successfully to: ${s.fileDialog.path}!');
								}

								s.overwriteSavedSomething = false;
								nextChart();
							});
						} else
							s.showOutput('Error: No difficulties found.');
					} catch (e:Exception) {
						s.showOutput('Error: ${e.message}', true);
						trace(e.stack);
					}
				});
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Update (Legacy)...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.fileDialog.open(function() {
				var oldSong = PlayState.SONG;
				try {
					var filePath:String = s.fileDialog.path.replace('\\', '/');
					filePath = filePath.substring(filePath.lastIndexOf('/') + 1, filePath.lastIndexOf('.'));

					var loadedChart:SwagSong = Song.parseJSON(s.fileDialog.data, filePath, '');
					if (loadedChart == null || !Reflect.hasField(loadedChart, 'song')) // Check if chart is ACTUALLY a chart and valid
					{
						s.showOutput('Error: File loaded is not a Psych Engine 0.x.x/FNF 0.2.x.x chart.', true);
						return;
					}

					var fmt:String = loadedChart.format;
					if (fmt == null || fmt.length < 1)
						fmt = loadedChart.format = 'unknown';

					if (!fmt.startsWith('psych_v1')) {
						loadedChart.format = 'psych_v1_convert';
						Song.convert(loadedChart);
						File.saveContent(s.fileDialog.path, PsychJsonPrinter.print(loadedChart, ['sectionNotes', 'events']));
						s.showOutput('Updated "$filePath" from format "$fmt" to "psych_v1" successfully!');
					} else
						s.showOutput('Chart is already up-to-date! Format: "$fmt"', true);
				} catch (e:Exception) {
					s.showOutput('Error: ${e.message}', true);
					trace(e.stack);
				}
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Preview (F12)', s.openEditorPlayState, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Playtest (Enter)', s.goToPlayState, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Exit', function() {
			PlayState.chartingMode = false;
			MusicBeatState.switchState(new editors.MasterEditorMenu());
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			FlxG.mouse.visible = false;
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
	}
}
