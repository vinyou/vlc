/*****************************************************************************
 * open.m: MacOS X plugin for vlc
 *****************************************************************************
 * Copyright (C) 2002 VideoLAN
 * $Id: open.m,v 1.4 2002/12/08 23:38:02 massiot Exp $
 *
 * Authors: Jon Lech Johansen <jon-vl@nanocrew.net> 
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#include <stdlib.h>                                      /* malloc(), free() */
#include <sys/param.h>                                    /* for MAXPATHLEN */
#include <string.h>

#include <paths.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOBSD.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IODVDMedia.h>

#import <Cocoa/Cocoa.h>

#include <vlc/vlc.h>
#include <vlc/intf.h>

#include "netutils.h"

#import "intf.h"
#import "playlist.h"
#import "open.h"

/*****************************************************************************
 * GetEjectableMediaOfClass 
 *****************************************************************************/
NSArray *GetEjectableMediaOfClass( const char *psz_class )
{
    io_object_t next_media;
    mach_port_t master_port;
    kern_return_t kern_result;
    NSArray *o_devices = nil;
    NSMutableArray *p_list = nil;
    io_iterator_t media_iterator;
    CFMutableDictionaryRef classes_to_match;

    kern_result = IOMasterPort( MACH_PORT_NULL, &master_port );
    if( kern_result != KERN_SUCCESS )
    {
        return( nil );
    }
    
    classes_to_match = IOServiceMatching( psz_class );
    if( classes_to_match == NULL )
    {
        return( nil );
    }
    
    CFDictionarySetValue( classes_to_match, CFSTR( kIOMediaEjectable ), 
                          kCFBooleanTrue );
    
    kern_result = IOServiceGetMatchingServices( master_port, classes_to_match, 
                                                &media_iterator );
    if( kern_result != KERN_SUCCESS )
    {
        return( nil );
    }

    p_list = [NSMutableArray arrayWithCapacity: 1];
    
    next_media = IOIteratorNext( media_iterator );
    if( next_media != NULL )
    {
        char psz_buf[0x32];
        size_t dev_path_length;
        CFTypeRef str_bsd_path;
    
        do
        {
            str_bsd_path = IORegistryEntryCreateCFProperty( next_media,
                                                            CFSTR( kIOBSDName ),
                                                            kCFAllocatorDefault,
                                                            0 );
            if( str_bsd_path == NULL )
            {
                IOObjectRelease( next_media );
                continue;
            }
            
            snprintf( psz_buf, sizeof(psz_buf), "%s%c", _PATH_DEV, 'r' );
            dev_path_length = strlen( psz_buf );
            
            if( CFStringGetCString( str_bsd_path,
                                    (char*)&psz_buf + dev_path_length,
                                    sizeof(psz_buf) - dev_path_length,
                                    kCFStringEncodingASCII ) )
            {
                [p_list addObject: [NSString stringWithCString: psz_buf]];
            }
            
            CFRelease( str_bsd_path );
            
            IOObjectRelease( next_media );
        
        } while( ( next_media = IOIteratorNext( media_iterator ) ) != NULL );
    }
    
    IOObjectRelease( media_iterator );

    o_devices = [NSArray arrayWithArray: p_list];

    return( o_devices );
}

/*****************************************************************************
 * VLCOpen implementation 
 *****************************************************************************/
@implementation VLCOpen

- (void)awakeFromNib
{
    [o_panel setTitle: _NS("Open Target")];

    [o_btn_ok setTitle: _NS("OK")];
    [o_btn_cancel setTitle: _NS("Cancel")];

    [[o_tabview tabViewItemAtIndex: 0] setLabel: _NS("File")];
    [[o_tabview tabViewItemAtIndex: 1] setLabel: _NS("Disc")];
    [[o_tabview tabViewItemAtIndex: 2] setLabel: _NS("Network")];

    [o_file_btn_browse setTitle: _NS("Browse...")];

    [o_disc_type_lbl setStringValue: _NS("Disc type")];
    [o_disc_device_lbl setStringValue: _NS("Device name")];
    [o_disc_title_lbl setStringValue: _NS("Title")];
    [o_disc_chapter_lbl setStringValue: _NS("Chapter")];

    [o_net_udp_port_lbl setStringValue: _NS("Port")];
    [o_net_udpm_addr_lbl setStringValue: _NS("Address")];
    [o_net_udpm_port_lbl setStringValue: _NS("Port")];
    [o_net_cs_addr_lbl setStringValue: _NS("Address")];
    [o_net_cs_port_lbl setStringValue: _NS("Port")];
    [o_net_http_url_lbl setStringValue: _NS("URL")];

    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openFilePathChanged:)
        name: NSControlTextDidChangeNotification
        object: o_file_path];

    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openDiscInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_disc_device];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openDiscInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_disc_title];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openDiscInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_disc_chapter];

    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_udp_port];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_udpm_addr];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_udpm_port];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_cs_addr];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_cs_port];
    [[NSNotificationCenter defaultCenter] addObserver: self
        selector: @selector(openNetInfoChanged:)
        name: NSControlTextDidChangeNotification
        object: o_net_http_url];
}

- (void)openTarget:(int)i_type
{
    int i_result;

    [o_tabview selectTabViewItemAtIndex: i_type];

    i_result = [NSApp runModalForWindow: o_panel];
    [o_panel close];

    if( i_result )
    {
        NSString *o_source = [o_mrl stringValue];

        [o_playlist appendArray: 
            [NSArray arrayWithObject: o_source] atPos: -1];
    }
}

- (void)tabView:(NSTabView *)o_tv didSelectTabViewItem:(NSTabViewItem *)o_tvi
{
    NSString *o_label = [o_tvi label];

    if( [o_label isEqualToString: _NS("File")] )
    {
        [self openFilePathChanged: nil];
    }
    else if( [o_label isEqualToString: _NS("Disc")] )
    {
        [self openDiscTypeChanged: nil];
    }
    else if( [o_label isEqualToString: _NS("Network")] )
    {
        [self openNetModeChanged: nil];
    }  
}

- (IBAction)openFileGeneric:(id)sender
{
    [self openFilePathChanged: nil];
    [self openTarget: 0];
}

- (IBAction)openDisc:(id)sender
{
    [self openDiscTypeChanged: nil];
    [self openTarget: 1];
}

- (IBAction)openNet:(id)sender
{
    [self openNetModeChanged: nil];
    [self openTarget: 2];
}

- (void)openFilePathChanged:(NSNotification *)o_notification
{
    NSString *o_mrl_string;
    NSString *o_filename = [o_file_path stringValue];

    o_mrl_string = [NSString stringWithFormat: @"file://%@", o_filename];
    [o_mrl setStringValue: o_mrl_string]; 
}

- (IBAction)openDiscTypeChanged:(id)sender
{
    NSString *o_type;
    NSArray *o_devices;
    const char *psz_class = NULL;
    
    [o_disc_device removeAllItems];
    
    o_type = [[o_disc_type selectedCell] title];

    if( [o_type isEqualToString: @"VCD"] )
    {
        psz_class = kIOCDMediaClass;
    }
    else
    {
        psz_class = kIODVDMediaClass;
    }
    
    o_devices = GetEjectableMediaOfClass( psz_class );
    if( o_devices != nil )
    {
        int i_devices = [o_devices count];
        
        if( i_devices )
        {
            int i;
        
            for( i = 0; i < i_devices; i++ )
            {
                [o_disc_device 
                    addItemWithObjectValue: [o_devices objectAtIndex: i]];
            }
            
            [o_disc_device selectItemAtIndex: 0];
        }
        else
        {
            [o_disc_device setStringValue: 
                [NSString stringWithFormat: @"No %@ found", o_type]];
        }
    }

    [self openDiscInfoChanged: nil];
}

- (IBAction)openDiscStepperChanged:(id)sender
{
    int i_tag = [sender tag];

    if( i_tag == 0 )
    {
        [o_disc_title setIntValue: [o_disc_title_stp intValue]];
    }
    else if( i_tag == 1 )
    {
        [o_disc_chapter setIntValue: [o_disc_chapter_stp intValue]];
    }

    [self openDiscInfoChanged: nil];
}

- (void)openDiscInfoChanged:(NSNotification *)o_notification
{
    NSString *o_type;
    NSString *o_device;
    NSString *o_mrl_string;
    int i_title, i_chapter;

    o_type = [[o_disc_type selectedCell] title];
    o_device = [o_disc_device stringValue];
    i_title = [o_disc_title intValue];
    i_chapter = [o_disc_chapter intValue];
    if( [o_type isEqualToString: @"VCD"] )
    {
        o_type = [NSString stringWithCString: "vcd"];
    }
    else if ( [o_type isEqualToString: @"DVD"] )
    {
        o_type = [NSString stringWithCString: "dvdold"];
    }
    else
    {
        o_type = [NSString stringWithCString: "dvdplay"];
    }

    
    o_mrl_string = [NSString stringWithFormat: @"%@://%@@%i,%i",
        o_type, o_device, i_title, i_chapter]; 

    [o_mrl setStringValue: o_mrl_string]; 
}

- (IBAction)openNetModeChanged:(id)sender
{
    NSString *o_mode;
    BOOL b_udp = FALSE;
    BOOL b_udpm = FALSE;
    BOOL b_cs = FALSE;
    BOOL b_http = FALSE;

    o_mode = [[o_net_mode selectedCell] title];

    if( [o_mode isEqualToString: @"UDP"] ) b_udp = TRUE;   
    else if( [o_mode isEqualToString: @"UDP Multicast"] ) b_udpm = TRUE;
    else if( [o_mode isEqualToString: @"Channel server"] ) b_cs = TRUE;
    else if( [o_mode isEqualToString: @"HTTP"] ) b_http = TRUE;

    [o_net_udp_port setEnabled: b_udp];
    [o_net_udp_port_stp setEnabled: b_udp];
    [o_net_udpm_addr setEnabled: b_udpm];
    [o_net_udpm_port setEnabled: b_udpm];
    [o_net_udpm_port_stp setEnabled: b_udpm];
    [o_net_cs_addr setEnabled: b_cs];
    [o_net_cs_port setEnabled: b_cs]; 
    [o_net_cs_port_stp setEnabled: b_cs]; 
    [o_net_http_url setEnabled: b_http];

    [self openNetInfoChanged: nil];
}

- (IBAction)openNetStepperChanged:(id)sender
{
    int i_tag = [sender tag];

    if( i_tag == 0 )
    {
        [o_net_udp_port setIntValue: [o_net_udp_port_stp intValue]];
    }
    else if( i_tag == 1 )
    {
        [o_net_udpm_port setIntValue: [o_net_udpm_port_stp intValue]];
    }
    else if( i_tag == 2 )
    {
        [o_net_cs_port setIntValue: [o_net_cs_port_stp intValue]];
    }

    [self openNetInfoChanged: nil];
}

- (void)openNetInfoChanged:(NSNotification *)o_notification
{
    NSString *o_mode;
    vlc_bool_t b_channel;
    NSString *o_mrl_string = [NSString string];
    intf_thread_t * p_intf = [NSApp getIntf];

    o_mode = [[o_net_mode selectedCell] title];

    b_channel = (vlc_bool_t)[o_mode isEqualToString: @"Channel server"]; 
    config_PutInt( p_intf, "network-channel", b_channel );

    if( [o_mode isEqualToString: @"UDP"] )
    {
        int i_port = [o_net_udp_port intValue];

        o_mrl_string = [NSString stringWithString: @"udp://"]; 

        if( i_port != 1234 )
        {
            o_mrl_string = 
                [o_mrl_string stringByAppendingFormat: @"@:%i", i_port]; 
        } 
    }
    else if( [o_mode isEqualToString: @"UDP Multicast"] ) 
    {
        NSString *o_addr = [o_net_udpm_addr stringValue];
        int i_port = [o_net_udpm_port intValue];

        o_mrl_string = [NSString stringWithFormat: @"udp://@%@", o_addr]; 

        if( i_port != 1234 )
        {
            o_mrl_string = 
                [o_mrl_string stringByAppendingFormat: @":%i", i_port]; 
        } 
    }
    else if( [o_mode isEqualToString: @"Channel server"] )
    {
        NSString *o_addr = [o_net_cs_addr stringValue];
        int i_port = [o_net_cs_port intValue];

        if( p_intf->p_vlc->p_channel == NULL )
        {
            network_ChannelCreate( p_intf );
        } 

        config_PutPsz( p_intf, "channel-server", [o_addr lossyCString] ); 
        if( i_port < 65536 )
        {
            config_PutInt( p_intf, "channel-port", i_port );
        }

        /* FIXME: we should use a playlist server instead */
        o_mrl_string = [NSString stringWithString: @"udp://"];
    }
    else if( [o_mode isEqualToString: @"HTTP"] )
    {
        NSString *o_url = [o_net_http_url stringValue];

        o_mrl_string = [NSString stringWithFormat: @"http://%@", o_url];
    }

    [o_mrl setStringValue: o_mrl_string];
}

- (IBAction)openFileBrowse:(id)sender
{
    NSOpenPanel *o_open_panel = [NSOpenPanel openPanel];
    
    [o_open_panel setAllowsMultipleSelection: NO];

    if( [o_open_panel runModalForDirectory: nil 
            file: nil types: nil] == NSOKButton )
    {
        NSString *o_filename = [[o_open_panel filenames] objectAtIndex: 0];
        [o_file_path setStringValue: o_filename];
        [self openFilePathChanged: nil];
    }
}

- (IBAction)openFile:(id)sender
{
    NSOpenPanel *o_open_panel = [NSOpenPanel openPanel];

    [o_open_panel setAllowsMultipleSelection: NO];

    if( [o_open_panel runModalForDirectory: nil
            file: nil types: nil] == NSOKButton )
    {
        [o_playlist appendArray: [o_open_panel filenames] atPos: -1];
    }
}

- (IBAction)panelCancel:(id)sender
{
    [NSApp stopModalWithCode: 0];
}

- (IBAction)panelOk:(id)sender
{
    if( [[o_mrl stringValue] length] )
    {
        [NSApp stopModalWithCode: 1];
    }
    else
    {
        NSBeep();
    }
}

@end
