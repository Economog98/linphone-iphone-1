/*
 * Copyright (c) 2010-2020 Belledonne Communications SARL.
 *
 * This file is part of linphone-iphone
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#import "UIChatBubblePhotoCell.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVKit/AVKit.h>

#define voicePlayer VIEW(ChatConversationView).sharedVoicePlayer
#define chatView VIEW(ChatConversationView)
#define FILE_ICON_TAG 0
#define REALIMAGE_TAG 1



@implementation UIChatBubblePhotoCell {
	FileTransferDelegate *_ftd;
    CGSize imageSize, bubbleSize, videoDefaultSize;
    ChatConversationTableView *chatTableView;
    BOOL assetIsLoaded;
}

#pragma mark - Lifecycle Functions

- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier]) != nil) {
		NSArray *arrayOfViews =
			[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(self.class) owner:self options:nil];
		// resize cell to match .nib size. It is needed when resized the cell to
		// correctly adapt its height too
		UIView *sub = nil;
		for (int i = 0; i < arrayOfViews.count; i++) {
			if ([arrayOfViews[i] isKindOfClass:UIView.class]) {
				sub = arrayOfViews[i];
				break;
			}
		}
		[self addSubview:sub];
        chatTableView = VIEW(ChatConversationView).tableController;
        videoDefaultSize = CGSizeMake(320, 240);
        assetIsLoaded = FALSE;
		self.contentView.userInteractionEnabled = NO;
		_contentViews = [[NSMutableArray alloc] init];
		
		
        self.vrView.layer.cornerRadius = 30.0f;
		self.vrView.layer.masksToBounds = YES;
        [self.innerView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onPopupMenuPressed)]];
        self.messageText.userInteractionEnabled = false;

	}
	return self;
}

- (void)onDelete {
    [super onDelete];
}

#pragma mark -
- (void)setEvent:(LinphoneEventLog *)event {
	if (!event || !(linphone_event_log_get_type(event) == LinphoneEventLogTypeConferenceChatMessage))
		return;

	[super setEvent:event];
	[self setChatMessage:linphone_event_log_get_chat_message(event)];
}

- (void)setChatMessage:(LinphoneChatMessage *)amessage {
	_imageGestureRecognizer.enabled = NO;
	_messageImageView.image = nil;
    _finalImage.image = nil;
    _finalImage.hidden = TRUE;
	_fileTransferProgress.progress = 0;
    assetIsLoaded = FALSE;

	/* As the cell UI will be reset, fileTransDelegate need to be reconnected. Otherwise, the UIProgressView will not work */
	[self disconnectFromFileDelegate];
	if (amessage) {
		for (FileTransferDelegate *aftd in [LinphoneManager.instance fileTransferDelegates]) {
			if (aftd.message == amessage && linphone_chat_message_get_state(amessage) == LinphoneChatMessageStateFileTransferInProgress) {
				LOGI(@"Chat message [%p] with file transfer delegate [%p], connecting to it!", amessage, aftd);
				[self connectToFileDelegate:aftd];
				break;
			}
		}
	}

	[super setChatMessageForCbs:amessage];
	[LinphoneManager setValueInMessageAppData:NULL forKey:@"encryptedfile" inMessage:self.message];
	[LinphoneManager setValueInMessageAppData:NULL forKey:@"encryptedfiles" inMessage:self.message];
}

- (void) loadImageAsset:(PHAsset*) asset  image:(UIImage *)image {
	_finalImage.tag = REALIMAGE_TAG;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_finalImage setImage:image];
        [_messageImageView setAsset:asset];
        [_messageImageView stopLoading];
        _messageImageView.hidden = YES;
        _finalImage.hidden = NO;
        _fileView.hidden = YES;
        [self layoutSubviews];
    });
}

- (void) loadAsset:(PHAsset *) asset {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.synchronous = TRUE;
    [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:PHImageManagerMaximumSize contentMode:PHImageContentModeDefault options:options
                                            resultHandler:^(UIImage *image, NSDictionary * info) {
                                                if (image) {
                                                    imageSize = [UIChatBubbleTextCell getMediaMessageSizefromOriginalSize:[image size] withWidth:chatTableView.tableView.frame.size.width - CELL_IMAGE_X_MARGIN];
                                                    [chatTableView.imagesInChatroom setObject:image forKey:[asset localIdentifier]];
                                                    [self loadImageAsset:asset image:image];
                                                }
                                                else {
                                                    LOGE(@"Can't read image");
                                                }
                                            }];
}

- (void) loadFileAsset:(NSString *)name {
	UIImage *image = [UIChatBubbleTextCell getImageFromFileName:name];
	[self loadImageAsset:nil image:image];
	_imageGestureRecognizer.enabled = YES;
	_finalImage.tag = FILE_ICON_TAG;
}

- (void) loadPlaceholder {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Change this to load placeholder image when no asset id
        //[_finalImage setImage:image];
        //[_messageImageView setAsset:asset];
        [_messageImageView stopLoading];
        _messageImageView.hidden = YES;
        _imageGestureRecognizer.enabled = YES;
        _finalImage.hidden = NO;
        [self layoutSubviews];
    });
}


- (void)update {
	if (self.message == nil) {
		LOGW(@"Cannot update message room cell: NULL message");
		return;
	}
	[super update];
	
	_vrPlayPause.enabled = linphone_core_get_calls_nb(LC) == 0;

	
	NSMutableDictionary<NSString *, NSString *> *encrptedFilePaths = NULL;
	if ([VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId]) {
		encrptedFilePaths = [LinphoneManager getMessageAppDataForKey:@"encryptedfiles" inMessage:self.message];
		if (!encrptedFilePaths) {
			encrptedFilePaths = [NSMutableDictionary dictionary];
		}
	}
	
	_voiceRecordingFile = nil;
	LinphoneContent *voiceContent = [UIChatBubbleTextCell voiceContent:self.message];
	if (voiceContent) {
		_voiceRecordingFile = [NSString stringWithUTF8String:[VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId] ? linphone_content_get_plain_file_path(voiceContent) : linphone_content_get_file_path(voiceContent)];
		if ([VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId])
			[encrptedFilePaths setValue:_voiceRecordingFile forKey:[NSString stringWithUTF8String:linphone_content_get_name(voiceContent)]];
		[self setVoiceMessageDuration];
		_vrWaveMaskPlayback.frame = CGRectZero;
		_vrWaveMaskPlayback.backgroundColor = linphone_chat_message_is_outgoing(self.message) ? UIColor.orangeColor : UIColor.grayColor;
	}
	
	const bctbx_list_t *contents = linphone_chat_message_get_contents(self.message);

	size_t contentCount = bctbx_list_size(contents);
	if (voiceContent)
		contentCount--;
	BOOL multiParts = ((linphone_chat_message_get_text_content(self.message) != NULL) ? bctbx_list_size(contents) > 2 : bctbx_list_size(contents) > 1);
	if (voiceContent && !multiParts) {
		_cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden = _playButton.hidden = _fileName.hidden = _fileView.hidden = _fileButton.hidden = YES;
		return;
	}
	
	if (multiParts) {
		if (!assetIsLoaded) {
			_imageGestureRecognizer.enabled = NO;
			_cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden = _playButton.hidden = _fileName.hidden = _fileView.hidden = _fileButton.hidden = YES;
			const bctbx_list_t *it = contents;
			int i;
			for (it = contents, i=0; it != NULL; it=bctbx_list_next(it)){
				LinphoneContent *content = (LinphoneContent *)it->data;
				if (linphone_content_is_voice_recording(content)) { // Handled elsewhere
					continue;
				}
				if (linphone_content_is_file_transfer(content) || linphone_content_is_file(content)){
					UIChatContentView *contentView = [[UIChatContentView alloc] initWithFrame: CGRectMake(0,0,0,0)];
					if([VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId] && (linphone_chat_message_is_outgoing(self.message) || linphone_content_is_file(content))) {
						// downloaded or ougoing message
						NSString *name = [NSString stringWithUTF8String:linphone_content_get_name(content)];
						NSString *filePath = [encrptedFilePaths valueForKey:name];
						if (filePath == NULL) {
							char *cPath = linphone_content_get_plain_file_path(content);
							if (cPath) {
								if (strcmp(cPath, "") != 0) {
									NSString *tempPath = [NSString stringWithUTF8String:cPath];
									NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
									filePath = [paths objectAtIndex:0];
									filePath = [filePath stringByAppendingPathComponent:name];
									[[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:filePath error:nil];
								}
								ms_free(cPath);
								[encrptedFilePaths setValue:filePath forKey:name];
							}
						}
						contentView.filePath = filePath;
					}
					[contentView setContent:content message:self.message];
					contentView.position = i;
					[_contentViews addObject:contentView];
					i++;
				}
			}
			if ([VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId]) {
				[LinphoneManager setValueInMessageAppData:encrptedFilePaths forKey:@"encryptedfiles" inMessage:self.message];
			}
			assetIsLoaded = TRUE;
			[self layoutSubviews];
		}
		return;
	}

	const char *url = linphone_chat_message_get_external_body_url(self.message);
	BOOL is_external =
		(url && (strstr(url, "http") == url)) || linphone_chat_message_get_file_transfer_information(self.message);
	NSString *localImage = [LinphoneManager getMessageAppDataForKey:@"localimage" inMessage:self.message];
	NSString *localVideo = [LinphoneManager getMessageAppDataForKey:@"localvideo" inMessage:self.message];
	NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
	NSString *filePath = [LinphoneManager getMessageAppDataForKey:@"encryptedfile" inMessage:self.message];
	assert(is_external || localImage || localVideo || localFile);

	LinphoneContent *fileContent = linphone_chat_message_get_file_transfer_information(self.message);
	if (fileContent == nil) {
		LOGW(@"file content is null");
		return;
	}
	
	BOOL is_outgoing = linphone_chat_message_is_outgoing(self.message);
	if (!is_outgoing) {
		LinphoneChatMessageState state = linphone_chat_message_get_state(self.message);
		if (state != LinphoneChatMessageStateFileTransferDone && state != LinphoneChatMessageStateDisplayed) {
			if (state == LinphoneChatMessageStateFileTransferInProgress) {
				_cancelButton.hidden = _fileTransferProgress.hidden = NO;
				_downloadButton.hidden = YES;
				_playButton.hidden = YES;
				_fileName.hidden = _fileView.hidden = _fileButton.hidden =YES;
			} else {
				_downloadButton.hidden =  YES;
				UIChatContentView * contentView = [[UIChatContentView alloc] init];
				[contentView setContent:fileContent message:self.message];
				contentView.position = 0;
				[_contentViews addObject:contentView];
				_cancelButton.hidden = _fileTransferProgress.hidden =  YES;
				_playButton.hidden = YES;
				_fileName.hidden = _fileView.hidden = _fileButton.hidden =  YES;
				[self layoutSubviews];
			}
			return;
		}
	}
	
	NSString *fileType = [NSString stringWithUTF8String:linphone_content_get_type(fileContent)];
	NSString *fileName = [NSString stringWithUTF8String:linphone_content_get_name(fileContent)];

	if (!filePath) {
		char *cPath = [VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId] ? linphone_content_get_plain_file_path(fileContent) : NULL;
		if (cPath) {
			if (strcmp(cPath, "") != 0) {
				NSString *tempPath = [NSString stringWithUTF8String:cPath];
				NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
				filePath = [paths objectAtIndex:0];
				filePath = [filePath stringByAppendingPathComponent:fileName];
				[[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:filePath error:nil];
			}
			ms_free(cPath);
			[LinphoneManager setValueInMessageAppData:filePath forKey:@"encryptedfile" inMessage:self.message];
		} else {
			filePath = [LinphoneManager validFilePath:fileName];
		}
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		// already downloaded
		if (!assetIsLoaded) {
			assetIsLoaded = TRUE;
			NSString *key = [ChatConversationView getKeyFromFileType:fileType fileName:fileName];
			if ([key isEqualToString:@"localimage"]) {
				// we did not load the image yet, so start doing so
				if (_messageImageView.image == nil) {
					NSData *data = [NSData dataWithContentsOfFile:filePath];
					UIImage *image = [[UIImage alloc] initWithData:data];
					if (image) {
						[self loadImageAsset:nil image:image];
						_imageGestureRecognizer.enabled = YES;
					} else {
						// compability with other platforms
						[self loadFileAsset:fileName];
					}
				}
			} else if ([key isEqualToString:@"localvideo"]) {
				if (_messageImageView.image == nil) {
					UIImage* image = [UIChatBubbleTextCell getImageFromVideoUrl:[NSURL fileURLWithPath:filePath]];
					if (image) {
						[self loadImageAsset:nil image:image];
						_imageGestureRecognizer.enabled = NO;
					} else {
						// compability with other platforms
						[self loadFileAsset:fileName];
					}
				}
			} else if ([key isEqualToString:@"localfile"]) {
				if ([fileType isEqualToString:@"video"]) {
					UIImage* image = [UIChatBubbleTextCell getImageFromVideoUrl:[NSURL fileURLWithPath:filePath]];
					[self loadImageAsset:nil image:image];
					_imageGestureRecognizer.enabled = NO;
				} else if ([fileName hasSuffix:@"JPG"] || [fileName hasSuffix:@"PNG"] || [fileName hasSuffix:@"jpg"] || [fileName hasSuffix:@"png"]) {
					NSData *data = [NSData dataWithContentsOfFile:filePath];
					UIImage *image = [[UIImage alloc] initWithData:data];
					[self loadImageAsset:nil image:image];
					_imageGestureRecognizer.enabled = YES;
				} else {
					[self loadFileAsset:fileName];
				}
			}

			if (!(localImage || localVideo || localFile)) {
				// If the file has been downloaded in background, save it in the folders and display it.
				[LinphoneManager setValueInMessageAppData:fileName forKey:key inMessage:self.message];
				dispatch_async(dispatch_get_main_queue(), ^ {
					if (![VFSUtil vfsEnabledWithGroupName:kLinphoneMsgNotificationAppGroupId] && [ConfigManager.instance lpConfigBoolForKeyWithKey:@"auto_write_to_gallery_preference"]) {
						[ChatConversationView writeMediaToGallery:fileName fileType:fileType];
					}
				});
			}
		}
		[self uploadingImage:fileType localFile:localFile];
	} else {
		// support previous methode:
		if (!(localImage || localVideo || localFile)) {
			_playButton.hidden = YES;
			_fileName.hidden = _fileView.hidden = _fileButton.hidden = YES;
			_messageImageView.hidden = _cancelButton.hidden = (_ftd.message == nil);
			_downloadButton.hidden = !_cancelButton.hidden;
			_fileTransferProgress.hidden = NO;
		} else {
			// file is being saved on device - just wait for it
			if ([localImage isEqualToString:@"saving..."] || [localVideo isEqualToString:@"saving..."] || [localFile isEqualToString:@"saving..."]) {
				_cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden = _playButton.hidden = _fileName.hidden = _fileView.hidden = _fileButton.hidden = YES;
			} else {
				if(!assetIsLoaded) {
					assetIsLoaded = TRUE;
					if (localImage) {
						// we did not load the image yet, so start doing so
						if (_messageImageView.image == nil) {
							[self loadFirstImage:localImage type:PHAssetMediaTypeImage];
							_imageGestureRecognizer.enabled = YES;
						}
					} else if (localVideo) {
						if (_messageImageView.image == nil) {
							[self loadFirstImage:localVideo type:PHAssetMediaTypeVideo];
							_imageGestureRecognizer.enabled = NO;
						}
					} else if (localFile) {
						if ([fileType isEqualToString:@"video"]) {
							UIImage* image = [UIChatBubbleTextCell getImageFromVideoUrl:[VIEW(ChatConversationView) getICloudFileUrl:localFile]];
							[self loadImageAsset:nil image:image];
							_imageGestureRecognizer.enabled = NO;
						} else if ([localFile hasSuffix:@"JPG"] || [localFile hasSuffix:@"PNG"] || [localFile hasSuffix:@"jpg"] || [localFile hasSuffix:@"png"]) {
							NSData *data = [NSData dataWithContentsOfURL:[VIEW(ChatConversationView) getICloudFileUrl:localFile]];
							UIImage *image = [[UIImage alloc] initWithData:data];
							[self loadImageAsset:nil image:image];
							_imageGestureRecognizer.enabled = YES;
						} else {
							[self loadFileAsset:fileName];
						}
					}
				}
			}
			[self uploadingImage:fileType localFile:localFile];
		}
	}
}

- (void)uploadingImage:(NSString *)fileType localFile:(NSString *)localFile {
	// we are uploading the image
	if (_ftd.message != nil) {
		_cancelButton.hidden = _fileTransferProgress.hidden = super.notDelivered ? YES : NO;
		_downloadButton.hidden = YES;
		_playButton.hidden = YES;
		_fileName.hidden = _fileView.hidden = _fileButton.hidden =YES;
	} else {
		_cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden =  YES;
		_playButton.hidden = ![fileType isEqualToString:@"video"];
		_fileName.hidden = _fileView.hidden = _fileButton.hidden = localFile ? NO : YES;
	}
}

- (void)loadFirstImage:(NSString *)key type:(PHAssetMediaType)type {
    [_messageImageView startLoading];
    PHFetchResult<PHAsset *> *assets = [LinphoneManager getPHAssets:key];
    UIImage *img = nil;
    
    img = [chatTableView.imagesInChatroom objectForKey:key];
    PHAsset *asset = [assets firstObject];
    if (!asset)
        [self loadPlaceholder];
    else if (asset.mediaType != type)
        img = nil;
    if (img)
        [self loadImageAsset:asset image:img];
    else
        [self loadAsset:asset];
}

- (void)fileErrorBlock {
    DTActionSheet *sheet = [[DTActionSheet alloc] initWithTitle:NSLocalizedString(@"Can't find this file", nil)];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [sheet addCancelButtonWithTitle:NSLocalizedString(@"OK", nil) block:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [sheet showInView:PhoneMainView.instance.view];
        });
    });
}

- (void)playVideoByPlayer:(AVPlayer *)player {
    AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
    [PhoneMainView.instance presentViewController:controller animated:YES completion:nil];
    controller.player = player;
    [player play];
}

- (IBAction)onDownloadClick:(id)event {
	[_ftd cancel];
	_ftd = [[FileTransferDelegate alloc] init];
	[self connectToFileDelegate:_ftd];
	[_ftd download:self.message];
	_cancelButton.hidden = NO;
	_downloadButton.hidden = YES;
    _playButton.hidden = YES;
    _fileName.hidden = _fileView.hidden = _fileButton.hidden = YES;
}

- (IBAction)onPlayClick:(id)sender {
	NSString *filePath = [LinphoneManager getMessageAppDataForKey:@"encryptedfile" inMessage:self.message];
	if (!filePath) {
		NSString *localVideo = [LinphoneManager getMessageAppDataForKey:@"localvideo" inMessage:self.message];
		NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
		filePath = [LinphoneManager validFilePath:(localVideo?:localFile)];
	}
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:filePath]];
		[self playVideoByPlayer:player];
		return;
	}

    PHAsset *asset = [_messageImageView asset];
    if (!asset) {
        NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
		NSURL *url = [VIEW(ChatConversationView) getICloudFileUrl:localFile];
        AVPlayer *player = [AVPlayer playerWithURL:url];
        [self playVideoByPlayer:player];
        return;
    }
    PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
   // options.synchronous = TRUE;
    [[PHImageManager defaultManager] requestPlayerItemForVideo:asset options:options resultHandler:^(AVPlayerItem * _Nullable playerItem, NSDictionary * _Nullable info) {
        if(playerItem) {
            AVPlayer *player = [AVPlayer playerWithPlayerItem:playerItem];
            [self playVideoByPlayer:player];
        } else {
            [self fileErrorBlock];
        }
    }];
}


- (IBAction)onFileClick:(id)sender {
    ChatConversationView *view = VIEW(ChatConversationView);
	NSString *filePath = [LinphoneManager getMessageAppDataForKey:@"encryptedfile" inMessage:self.message];
	if (filePath) {
		[view openFileWithURL:[NSURL fileURLWithPath:filePath]];
		return;
	}
    NSString *name = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
	if([[NSFileManager defaultManager] fileExistsAtPath: [LinphoneManager validFilePath:name]]) {
		[view openFileWithURL:[ChatConversationView getFileUrl:name]];
	} else {
		[view openFileWithURL:[view getICloudFileUrl:name]];
	}
}


- (IBAction)onCancelClick:(id)sender {
	FileTransferDelegate *tmp = _ftd;
	[self disconnectFromFileDelegate];
	_fileTransferProgress.progress = 0;
	[tmp cancel];
	if (!linphone_core_is_network_reachable(LC)) {
		[self update];
	}
}


- (IBAction)onImageClick:(id)event {
	if (_finalImage.tag == FILE_ICON_TAG) {
		[self onFileClick:nil];
		return;
	}
	LinphoneChatMessageState state = linphone_chat_message_get_state(self.message);
	if (state == LinphoneChatMessageStateNotDelivered) {
		return;
	} else {
		if (![_messageImageView isLoading]) {
			ImageView *view = VIEW(ImageView);
			[PhoneMainView.instance changeCurrentView:view.compositeViewDescription];
			NSString *filePath = [LinphoneManager getMessageAppDataForKey:@"encryptedfile" inMessage:self.message];
			if (filePath) {
				NSData *data = [NSData dataWithContentsOfFile:filePath];
				UIImage *image = [[UIImage alloc] initWithData:data];
				[view setImage:image];
				return;
			}

			NSString *localImage = [LinphoneManager getMessageAppDataForKey:@"localimage" inMessage:self.message];
			NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
			NSString *imageName = NULL;
			if (localImage && [[NSFileManager defaultManager] fileExistsAtPath: [LinphoneManager validFilePath:localImage]]) {
				imageName = localImage;
			} else if (localFile && [[NSFileManager defaultManager] fileExistsAtPath:[LinphoneManager validFilePath:localFile]]) {
				if ([localFile hasSuffix:@"JPG"] || [localFile hasSuffix:@"PNG"] || [localFile hasSuffix:@"jpg"] || [localFile hasSuffix:@"png"]) {
					imageName = localFile;
				}
			}

			if (imageName) {
				NSData *data = [NSData dataWithContentsOfFile:[LinphoneManager validFilePath:imageName]];
				UIImage *image = [[UIImage alloc] initWithData:data];
				if (image)
					[view setImage:image];
				else
					LOGE(@"Can't read image");
				return;
			}

            PHAsset *asset = [_messageImageView asset];
            if (!asset) {
                return;
            }
            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.synchronous = TRUE;
            [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:PHImageManagerMaximumSize contentMode:PHImageContentModeDefault options:options
                                                    resultHandler:^(UIImage *image, NSDictionary * info) {
                                                        if (image) {
                                                            [view setImage:image];
                                                        }
                                                        else {
                                                            LOGE(@"Can't read image");
                                                        }
                                                    }];
		}
	}
}

#pragma mark - LinphoneFileTransfer Notifications Handling

- (void)connectToFileDelegate:(FileTransferDelegate *)aftd {
	if (aftd.message && linphone_chat_message_get_state(aftd.message) == LinphoneChatMessageStateFileTransferError) {
		LOGW(@"This file transfer failed unexpectedly, cleaning it");
		[aftd stopAndDestroy];
		return;
	}

	_ftd = aftd;
	_fileTransferProgress.progress = 0;
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(onFileTransferSendUpdate:)
											   name:kLinphoneFileTransferSendUpdate
											 object:_ftd];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(onFileTransferRecvUpdate:)
											   name:kLinphoneFileTransferRecvUpdate
											 object:_ftd];
}

- (void)disconnectFromFileDelegate {
	[NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneFileTransferSendUpdate object:_ftd];
    [NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneFileTransferRecvUpdate object:_ftd];
	_ftd = nil;
}

- (void)onFileTransferSendUpdate:(NSNotification *)notif {
	LinphoneChatMessageState state = [[[notif userInfo] objectForKey:@"state"] intValue];

	if (state == LinphoneChatMessageStateInProgress || state == LinphoneChatMessageStateFileTransferInProgress) {
		float progress = [[[notif userInfo] objectForKey:@"progress"] floatValue];
		// When uploading a file, the self.message file is first uploaded to the server,
		// so we are in progress state. Then state goes to filetransfertdone. Then,
		// the exact same self.message is sent to the other participant and we come
		// back to in progress again. This second time is NOT an upload, so we must
		// not update progress!
		_fileTransferProgress.progress = MAX(_fileTransferProgress.progress, progress);
		_fileTransferProgress.hidden = _cancelButton.hidden = (_fileTransferProgress.progress == 1.f);
	} else {
		ChatConversationView *view = VIEW(ChatConversationView);
		[view.tableController updateEventEntry:self.event];
		[view.tableController scrollToBottom:true];
	}
}
- (void)onFileTransferRecvUpdate:(NSNotification *)notif {
	LinphoneChatMessageState state = [[[notif userInfo] objectForKey:@"state"] intValue];
	if (state == LinphoneChatMessageStateInProgress || state == LinphoneChatMessageStateFileTransferInProgress) {
		float progress = [[[notif userInfo] objectForKey:@"progress"] floatValue];
		_fileTransferProgress.progress = MAX(_fileTransferProgress.progress, progress);
		_fileTransferProgress.hidden = _cancelButton.hidden = (_fileTransferProgress.progress == 1.f);
	} else {
		ChatConversationView *view = VIEW(ChatConversationView);
		[view.tableController updateEventEntry:self.event];
		[view.tableController scrollToBottom:true];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
    BOOL is_outgoing = linphone_chat_message_is_outgoing(super.message);
    CGRect bubbleFrame = super.bubbleView.frame;
    int origin_x;
    
    bubbleSize = [UIChatBubbleTextCell ViewSizeForMessage:[self message] withWidth:chatTableView.tableView.frame.size.width];
    
    bubbleFrame.size = bubbleSize;
    
    if (chatTableView.tableView.isEditing) {
        origin_x = 0;
    } else {
        origin_x = (is_outgoing ? self.frame.size.width - bubbleFrame.size.width : 0);
    }
    
    bubbleFrame.origin.x = origin_x;

    super.bubbleView.frame = bubbleFrame;

	if (_contentViews.count > 0) {
		// Positioning contentViews
		CGFloat imagesw=0;
		CGFloat max_imagesh=0;
		CGFloat max_imagesw=0;
		CGFloat originy=0;
		CGFloat originx=-IMAGE_DEFAULT_MARGIN;
		CGFloat availableWidth = chatTableView.tableView.frame.size.width-CELL_IMAGE_X_MARGIN;

		NSMutableArray<NSURL *> *fileUrls = [[NSMutableArray alloc] init];
		for (UIChatContentView *contentView in _contentViews) {
			if (contentView.filePath) {
				[fileUrls addObject:[NSURL fileURLWithPath:contentView.filePath]];
			}
		}
		for (UIChatContentView *contentView in _contentViews) {
			UIImage *image = contentView.image;
			CGSize sSize = [UIChatBubbleTextCell getMediaMessageSizefromOriginalSize:image.size withWidth:IMAGE_DEFAULT_WIDTH];
			imagesw += sSize.width;
			if (imagesw > availableWidth) {
				imagesw = sSize.width;
				max_imagesw = MAX(max_imagesw, imagesw);
				originy = max_imagesh+IMAGE_DEFAULT_MARGIN;
				max_imagesh += sSize.height;
				originx = sSize.width;
			} else {
				max_imagesw = MAX(max_imagesw, imagesw);
				max_imagesh = MAX(max_imagesh, sSize.height);
				originx += (sSize.width+IMAGE_DEFAULT_MARGIN);
			}

			[contentView setFrame:CGRectMake(originx-sSize.width, originy, sSize.width, sSize.height)];
			contentView.fileUrls = fileUrls;
			[_finalAssetView addSubview:contentView];
		}
		CGRect imgFrame = self.finalAssetView.frame;
		imgFrame.size = CGSizeMake(max_imagesw, max_imagesh);
		self.finalAssetView.frame = imgFrame;
		_finalImage.hidden = YES;
	} else {
		// Resizing Image view
		if (_finalImage.image) {
			CGRect imgFrame = self.finalAssetView.frame;
			imgFrame.size = [UIChatBubbleTextCell getMediaMessageSizefromOriginalSize:[_finalImage.image size] withWidth:chatTableView.tableView.frame.size.width - CELL_IMAGE_X_MARGIN];
			imgFrame.origin.x = (self.innerView.frame.size.width - imgFrame.size.width-17)/2;
			self.finalAssetView.frame = imgFrame;
		}
	}

    // Positioning text message
    const char *utf8Text = linphone_chat_message_get_text_content(self.message);
    
    CGRect textFrame = self.messageText.frame;
	if (_contentViews.count > 0 || _finalImage.image)
		textFrame.origin = CGPointMake(textFrame.origin.x, self.finalAssetView.frame.origin.y + self.finalAssetView.frame.size.height);
    else
        // When image hasn't be download
		textFrame.origin = CGPointMake(textFrame.origin.x, _voiceRecordingFile ? _fileView.frame.origin.y :  _imageSubView.frame.size.height + _imageSubView.frame.origin.y - 10);
    if (!utf8Text) {
        textFrame.size.height = 0;
    } else {
        textFrame.size.height = bubbleFrame.size.height - 90;//textFrame.origin.x;
    }
	
	if (_voiceRecordingFile) {
		CGRect vrFrame = _vrView.frame;
		vrFrame.origin.y = _contentViews.count == 0 && !utf8Text ? _fileView.frame.origin.y : textFrame.origin.y;
		_vrView.frame = vrFrame;
		textFrame.origin.y += VOICE_RECORDING_PLAYER_HEIGHT;
		_vrView.hidden = NO;
	} else {
		_vrView.hidden = YES;
	}
	
	CGRect r = super.photoCellContentView.frame;
	r.origin.y = linphone_chat_message_is_reply(super.message) ? super.replyView.view.frame.origin.y + super.replyView.view.frame.size.height + 10 : 7 ;
	super.photoCellContentView.frame = r;
	
	r = super.photoCellContentView.frame;
	r.origin.y = linphone_chat_message_is_forward(super.message) ? super.contactDateLabel.frame.origin.y + super.contactDateLabel.frame.size.height + 3 : r.origin.y;
	super.photoCellContentView.frame = r;
    
    self.messageText.frame = textFrame;
}

// Voice messages

static AVAudioPlayer* utilityPlayer;

-(void) setVoiceMessageDuration {
	NSError *error = nil;
	AVAudioPlayer* utilityPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:[NSURL URLWithString:_voiceRecordingFile] error:&error]; // Workaround as opening multiple linphone_players at the same time can cause crash (here for example layout refreshed whilst a voice memo is playing
	_vrTimerLabel.text =  [self formattedDuration:utilityPlayer.duration];
	utilityPlayer = nil;
}

-(void) voicePlayTimerUpdate {
	CGRect r = _vrWaveMaskPlayback.frame;
	r.size.width += _vrView.frame.size.width / ((linphone_player_get_duration(voicePlayer) / 500)) ;
	if (r.size.width > _vrView.frame.size.width) {
		r.size.width = _vrView.frame.size.width;
	}
	[UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear animations:^{
		_vrWaveMaskPlayback.frame = r;
		}completion:^(BOOL finished) {}];
}


-(void) stopPlayer {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[chatView stopSharedPlayer];
	[_vrPlayPause setImage:[UIImage imageNamed:@"vr_play"] forState:UIControlStateNormal];
	[_vrPlayerTimer invalidate];
	_vrWaveMaskPlayback.frame = CGRectZero;
}

-(NSString *)formattedDuration:(long)valueMs {
	return [NSString stringWithFormat:@"%02ld:%02ld", valueMs/ 60, (valueMs % 60) ];
}

-(void) startPlayer {
	[chatView startSharedPlayer:_voiceRecordingFile.UTF8String];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(stopPlayer)
											   name:kLinphoneVoiceMessagePlayerLostFocus
											 object:nil];
	
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(stopPlayer)
											   name:kLinphoneVoiceMessagePlayerEOF
											 object:nil];
	
	[_vrPlayPause setImage:[UIImage imageNamed:@"vr_stop"] forState:UIControlStateNormal];
	CGRect r = CGRectZero;
	r.size.height = _vrView.frame.size.height - 14;
	r.origin.y = 7;
	_vrWaveMaskPlayback.frame = r;
	_vrPlayerTimer =  [NSTimer scheduledTimerWithTimeInterval:0.5
													target:self
												  selector:@selector(voicePlayTimerUpdate)
												  userInfo:nil
												   repeats:YES];
	[self voicePlayTimerUpdate];

}

- (IBAction)onVRPlayPauseClick:(id)sender {
	if ([chatView sharedPlayedIsPlaying:_voiceRecordingFile.UTF8String])
		[self stopPlayer];
	else {
		[self startPlayer];
	}
}


//  menu

-(void) onPopupMenuPressed {
	[super onPopupMenuPressed];
}


@end


