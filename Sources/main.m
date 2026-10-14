#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>
#import <sys/file.h>
#import <fcntl.h>

static NSColor *Ink(void) { return [NSColor colorWithRed:.035 green:.055 blue:.07 alpha:1]; }
static NSColor *Mint(void) { return [NSColor colorWithRed:.49 green:.94 blue:.73 alpha:1]; }
static NSColor *Muted(void) { return [NSColor colorWithRed:.48 green:.59 blue:.62 alpha:1]; }
static NSColor *Amber(void) { return [NSColor colorWithRed:1 green:.73 blue:.37 alpha:1]; }
static NSColor *Coral(void) { return [NSColor colorWithRed:1 green:.43 blue:.44 alpha:1]; }
static id Safe(id value) { return value == NSNull.null ? nil : value; }
static NSString *Compact(double n) { if(n>=1e6)return [NSString stringWithFormat:@"%.2fM",n/1e6]; if(n>=1e3)return [NSString stringWithFormat:@"%.1fK",n/1e3];return [NSString stringWithFormat:@"%.0f",n]; }
static NSString *WindowName(double minutes) { if(minutes>=1440)return [NSString stringWithFormat:@"%.0f天",minutes/1440]; if(minutes>=60)return [NSString stringWithFormat:@"%.0f小时",minutes/60];return [NSString stringWithFormat:@"%.0f分钟",minutes]; }
static NSString *PhaseName(NSString *phase) { return @{@"working":@"处理任务",@"reading":@"检索资料",@"writing":@"修改文件",@"testing":@"验证结果",@"waiting":@"等待确认",@"done":@"任务完成",@"error":@"任务失败",@"idle":@"待命"}[phase] ?: @"待命"; }
static void FillPixel(CGFloat x,CGFloat y,CGFloat w,CGFloat h,NSColor *color) { [color setFill];NSRectFillUsingOperation(NSMakeRect(x,y,w,h),NSCompositingOperationSourceOver); }
static void Text(NSString *text,CGFloat x,CGFloat y,CGFloat size,NSColor *color,CGFloat width) {
    NSMutableParagraphStyle *p=[NSMutableParagraphStyle new];p.lineBreakMode=NSLineBreakByTruncatingTail;
    [text ?: @"" drawInRect:NSMakeRect(x,y,width,ceil(size*1.8)) withAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:p}];
}
static void PixelBox(NSRect r, NSColor *color) {
    CGFloat s=6;NSBezierPath *p=[NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(r.origin.x+s,r.origin.y)];
    [p lineToPoint:NSMakePoint(NSMaxX(r)-s,r.origin.y)];[p lineToPoint:NSMakePoint(NSMaxX(r)-s,r.origin.y+s)];
    [p lineToPoint:NSMakePoint(NSMaxX(r),r.origin.y+s)];[p lineToPoint:NSMakePoint(NSMaxX(r),NSMaxY(r)-s)];
    [p lineToPoint:NSMakePoint(NSMaxX(r)-s,NSMaxY(r)-s)];[p lineToPoint:NSMakePoint(NSMaxX(r)-s,NSMaxY(r))];
    [p lineToPoint:NSMakePoint(r.origin.x+s,NSMaxY(r))];[p lineToPoint:NSMakePoint(r.origin.x+s,NSMaxY(r)-s)];
    [p lineToPoint:NSMakePoint(r.origin.x,NSMaxY(r)-s)];[p lineToPoint:NSMakePoint(r.origin.x,r.origin.y+s)];
    [p lineToPoint:NSMakePoint(r.origin.x+s,r.origin.y+s)];[p closePath];[color setFill];[p fill];
}

static NSString *ChatKey(NSDictionary *task) { return task[@"navigateId"]?:task[@"rootId"]?:task[@"id"]?:@"idle"; }
static NSUInteger ChatHash(NSDictionary *task) {NSUInteger h=2166136261;for(NSUInteger i=0;i<ChatKey(task).length;i++){h^=[ChatKey(task) characterAtIndex:i];h*=16777619;}return h;}
static NSColor *ChatColor(NSDictionary *task) {if(!task)return Mint();NSUInteger hash=ChatHash(task);CGFloat hues[]={.00,.075,.15,.33,.50,.62,.76};return [NSColor colorWithCalibratedHue:hues[(hash/12)%7] saturation:.70 brightness:.98 alpha:1];}
static void DrawCharacter(NSDictionary *task,NSUInteger tick,CGFloat x,CGFloat y,CGFloat scale) {
    NSArray *sprites=@[
      @[@"000011110000",@"001111111100",@"011111111110",@"011111100000",@"111111000000",@"111110000000",@"111111000000",@"011111100000",@"011111111110",@"001111111100",@"000011110000",@"000000000000"],
      @[@"000111110000",@"001111111100",@"001222200000",@"012222222000",@"012222222200",@"001222220000",@"000111100000",@"011133111000",@"111333311100",@"222333322200",@"000330330000",@"001110111000"],
      @[@"000111110000",@"001122211000",@"011122211100",@"111111111110",@"122111112210",@"122111112210",@"111111111110",@"001222210000",@"001232310000",@"001222210000",@"000222200000",@"000000000000"],
      @[@"000001000000",@"000011100000",@"000011100000",@"111111111110",@"011111111100",@"001313131000",@"001313131000",@"001111111000",@"011111111100",@"011100011100",@"110000000110",@"000000000000"],
      @[@"000111110000",@"001111111000",@"011111111100",@"111221122110",@"111231132110",@"111111111110",@"111111111110",@"111111111110",@"111111111110",@"111111111110",@"110110110110",@"100100100010"],
      @[@"010000000010",@"011000000110",@"011111111110",@"011111111110",@"011311113110",@"011111111110",@"001113111100",@"000111111000",@"000111111010",@"001111111110",@"001111111100",@"001100001100"],
      @[@"000110011000",@"000110011000",@"000110011000",@"000110011000",@"001111111100",@"011111111110",@"011311113110",@"011111111110",@"001113111100",@"000111111000",@"001111111100",@"001110011100"],
      @[@"000000000000",@"000000000000",@"000011110000",@"001111111100",@"011111111110",@"111111111111",@"111311113111",@"111111111111",@"111111111111",@"011133331110",@"001111111100",@"000000000000"],
      @[@"000001000000",@"000011100000",@"000011100000",@"000111110000",@"000122210000",@"000123210000",@"000122210000",@"001111111000",@"011111111100",@"011001001100",@"000011100000",@"000001000000"],
      @[@"000001000000",@"000011100000",@"001111111100",@"001223322100",@"001223322100",@"001111111100",@"000111111000",@"011111111110",@"010113311010",@"010111111010",@"000110011000",@"001110011100"],
      @[@"001000000100",@"000100001000",@"001111111100",@"011011110110",@"111111111111",@"110111111011",@"110100001011",@"000110011000",@"001000000100",@"010000000010",@"000000000000",@"000000000000"],
      @[@"000111111000",@"001111111100",@"001222222100",@"011232232110",@"011222222110",@"011221122110",@"111222222111",@"111222222111",@"011222222110",@"001222222100",@"001111111100",@"011100001110"]];
    NSUInteger kind=ChatHash(task)%12;NSArray *sprite=sprites[kind];NSColor *accent=ChatColor(task);
    for(NSUInteger r=0;r<sprite.count;r++)for(NSUInteger c=0;c<[sprite[r] length];c++){
        unichar pixel=[sprite[r] characterAtIndex:c];if(pixel=='0')continue;
        NSColor *color=pixel=='2'?[NSColor colorWithWhite:.96 alpha:1]:(pixel=='3'?Ink():accent);
        if(kind==0 && tick%8<4 && r>=3 && r<=7 && c>=8)color=accent;
        FillPixel(x+c*scale,y+r*scale,scale,scale,color);
    }
}

@interface PixelTabButton:NSButton
@property BOOL activeTab;
@property NSColor *accent;
@end
@implementation PixelTabButton
- (BOOL)isFlipped {return YES;}
- (BOOL)mouseDownCanMoveWindow {return NO;}
- (void)drawRect:(NSRect)dirty {
    [NSGraphicsContext.currentContext setShouldAntialias:NO];
    BOOL active=self.activeTab;
    PixelBox(self.bounds,active?(self.accent?:Mint()):[NSColor colorWithRed:.19 green:.29 blue:.30 alpha:1]);
    PixelBox(NSInsetRect(self.bounds,2,2),self.highlighted?[NSColor colorWithRed:.12 green:.23 blue:.20 alpha:1]:Ink());
    NSColor *color=active?(self.accent?:Mint()):Muted();
    FillPixel(10,10,4,4,color);FillPixel(16,10,4,4,color);
    FillPixel(10,16,4,4,color);if(active)FillPixel(16,16,4,4,color);
    Text(self.title,27,5,11,color,self.bounds.size.width-34);
}
@end

@interface IslandPanel:NSPanel @end
@implementation IslandPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface PixelView:NSView
@property NSDictionary *snapshot;
@property NSDictionary *selected;
@property BOOL expanded;
@property NSUInteger tick;
@end
@implementation PixelView
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)robotAtX:(CGFloat)x y:(CGFloat)y scale:(CGFloat)s phase:(NSString *)phase {
    DrawCharacter(self.selected,self.tick,x,y,s);
}
- (void)sceneAtY:(CGFloat)top phase:(NSString *)phase {
    PixelBox(NSMakeRect(18,top,444,166),[NSColor colorWithRed:.065 green:.09 blue:.115 alpha:1]);
    for(int x=28;x<456;x+=12)for(int y=top+12;y<top+158;y+=12)FillPixel(x,y,1,1,[NSColor colorWithWhite:1 alpha:.05]);
    BOOL active=![phase isEqual:@"idle"]&&![phase isEqual:@"done"]&&![phase isEqual:@"error"];
    CGFloat bob=active?(self.tick%4<2?0:3):0;
    [self robotAtX:54 y:top+46+bob scale:4 phase:phase];
    FillPixel(48,top+113,76,3,Muted());
    FillPixel(151,top+77,20,3,Mint());FillPixel(168,top+72,3,13,Mint());
    Text(@"LIVE ACTIVITY",36,top+14,9,Muted(),150);
    Text(PhaseName(phase),35,top+135,11,Mint(),135);
    // Concrete stage illustration: documents, terminal, validation board, or waiting bubble.
    if([phase isEqual:@"reading"]){
        for(int i=2;i>=0;i--){FillPixel(214+i*12,top+42-i*8,76,78,Muted());FillPixel(217+i*12,top+45-i*8,70,72,Ink());}
        for(int i=0;i<5;i++)FillPixel(244,top+37+i*12,36+(i%2)*12,3,Mint());
        FillPixel(312,top+66,24,24,Mint());FillPixel(315,top+69,18,18,Ink());FillPixel(335,top+90,12,5,Mint());
        Text(@"READ > FIND > CONNECT",202,top+138,9,Muted(),235);
    }else if([phase isEqual:@"testing"]||[phase isEqual:@"done"]){
        FillPixel(214,top+38,166,86,Muted());FillPixel(217,top+41,160,80,Ink());
        for(int i=0;i<3;i++){FillPixel(231,top+55+i*20,9,9,Mint());FillPixel(249,top+58+i*20,100-i*16,3,Mint());}
        Text(@"CHECKS / RESULTS",215,top+138,9,Muted(),210);
    }else if([phase isEqual:@"waiting"]){
        PixelBox(NSMakeRect(215,top+43,138,76),Amber());PixelBox(NSMakeRect(218,top+46,132,70),Ink());
        for(int i=0;i<3;i++)FillPixel(248+i*24,top+76,6,6,i==(self.tick%3)?Amber():Muted());
        Text(@"YOUR INPUT NEEDED",214,top+138,9,Amber(),220);
    }else if([phase isEqual:@"idle"]){
        FillPixel(219,top+88,150,3,Muted());FillPixel(238,top+71,12,17,Mint());FillPixel(254,top+56,12,32,Mint());FillPixel(270,top+71,12,17,Mint());
        Text(@"READY WHEN YOU ARE",214,top+138,9,Muted(),210);
    }else{
        FillPixel(210,top+37,180,89,Muted());FillPixel(213,top+40,174,83,Ink());FillPixel(213,top+40,174,12,[NSColor colorWithRed:.12 green:.18 blue:.21 alpha:1]);
        FillPixel(220,top+44,4,4,Amber());FillPixel(228,top+44,4,4,Mint());
        for(int i=0;i<4;i++){FillPixel(224,top+65+i*12,7,3,Mint());FillPixel(242,top+65+i*12,40+(i%3)*28,3,i%2?Muted():Mint());}
        if(active)FillPixel(331+(self.tick%4)*9,top+102,6,8,Amber());
        FillPixel(270,top+126,60,4,Muted());
        Text([phase isEqual:@"writing"]?@"EDIT > BUILD > SHIP":@"EXECUTE / PROCESS",214,top+138,9,Muted(),220);
    }
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext.currentContext setShouldAntialias:NO];
    PixelBox(self.bounds,ChatColor(self.selected));
    PixelBox(NSInsetRect(self.bounds,2,2),Ink());
    NSString *phase=Safe(self.selected[@"phase"]) ?: @"idle";
    [self robotAtX:16 y:7 scale:2 phase:phase];
    Text(@"CODEX",49,9,12,ChatColor(self.selected),62);
    NSUInteger count=[self.snapshot[@"runningCount"] unsignedIntegerValue];
    NSUInteger unread=[self.snapshot[@"unreadCount"] unsignedIntegerValue];
    Text(unread?[NSString stringWithFormat:@"%lu运行/%lu未读",(unsigned long)count,(unsigned long)unread]:[NSString stringWithFormat:@"%lu 运行",(unsigned long)count],116,11,9,unread?Amber():Muted(),88);
    NSDictionary *quota=Safe(self.snapshot[@"quota"]);
    NSArray *windows=Safe(quota[@"windows"]);
    NSDictionary *window=windows.count?windows.firstObject:nil;
    if(window){
        double used=[window[@"usedPercent"] doubleValue];
        Text([NSString stringWithFormat:@"%@已用%.0f%%",WindowName([window[@"minutes"] doubleValue]),used],205,11,10,NSColor.whiteColor,117);
        for(int i=0;i<15;i++)FillPixel(327+i*6,15,4,8,i<ceil(used*15/100)?ChatColor(self.selected):[NSColor colorWithWhite:1 alpha:.12]);
    }else Text(@"用量未同步",233,11,11,Muted(),165);
    Text(self.expanded?@"▴":@"▾",450,9,12,ChatColor(self.selected),18);
    if(!self.expanded)return;
    FillPixel(18,39,444,1,[NSColor colorWithWhite:1 alpha:.12]);

    if([Safe(self.snapshot[@"tasks"]) count]>2)Text(@"向下滚动 ↓",370,53,9,ChatColor(self.selected),90);
    CGFloat footer=self.bounds.size.height-64;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSTimeInterval updated=[quota[@"updatedAt"] doubleValue];
    NSString *fresh=updated>0?[NSString stringWithFormat:@"用量报告 %.0f秒前 · 本机每2秒同步",MAX(0,now-updated)]:@"等待 Codex 返回用量报告";
    Text(fresh,20,footer,9,Muted(),440);
    NSString *detail=@"";
    if(windows.count>1){NSDictionary *second=windows[1];detail=[NSString stringWithFormat:@"%@窗口已用 %.0f%% · ",WindowName([second[@"minutes"] doubleValue]),[second[@"usedPercent"] doubleValue]];}
    if(window[@"resetsAt"] && window[@"resetsAt"]!=NSNull.null){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM/dd HH:mm";detail=[detail stringByAppendingFormat:@"重置 %@",[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[window[@"resetsAt"] doubleValue]]]];}
    Text(detail,20,footer+17,9,Muted(),440);
    Text(@"像素图呈现操作状态 · TOKEN含缓存输入",20,footer+39,9,Muted(),440);
}
@end

static const CGFloat TaskRowHeight=156;
static NSURL *ThreadURL(NSString *threadID) {
    if(![threadID isKindOfClass:NSString.class] || !threadID.length)return nil;
    NSMutableCharacterSet *allowed=[NSMutableCharacterSet alphanumericCharacterSet];[allowed addCharactersInString:@"-_"];
    NSString *encoded=[threadID stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return [NSURL URLWithString:[@"codex://threads/" stringByAppendingString:encoded]];
}

static void DrawTaskCard(NSDictionary *task,NSUInteger tick,NSRect bounds,BOOL highlighted) {
    [NSGraphicsContext.currentContext setShouldAntialias:NO];
    CGFloat w=bounds.size.width;
    NSString *phase=Safe(task[@"phase"])?:@"working";
    NSColor *accent=ChatColor(task);
    NSRect card=NSMakeRect(0,3,w,148);
    PixelBox(card,[accent colorWithAlphaComponent:highlighted?1:.55]);
    PixelBox(NSInsetRect(card,1,1),[NSColor colorWithRed:.06 green:.09 blue:.115 alpha:1]);
    FillPixel(12,17,3,10,accent);
    Text(Safe(task[@"title"])?:@"Codex 任务",24,13,12,NSColor.whiteColor,w-54);
    Text(@"↗",w-24,13,13,accent,20);
    PixelView *artist=[PixelView new];artist.tick=tick;artist.selected=task;
    [artist robotAtX:12 y:47 scale:2 phase:phase];
    NSString *phaseLabel=[task[@"unread"] boolValue]?@"✓ 本轮结束 · 未查看":([task[@"isSubtask"] boolValue]?[@"子任务 · " stringByAppendingString:PhaseName(phase)]:PhaseName(phase));
    if([task[@"status"] isEqual:@"running"] && [task[@"unreadCount"] unsignedIntegerValue])phaseLabel=[NSString stringWithFormat:@"运行中 · %@条未查看",task[@"unreadCount"]];
    Text(phaseLabel,50,42,11,accent,w-155);
    Text([NSString stringWithFormat:@"%@ TOKEN · IN %@ / OUT %@",Compact([task[@"tokens"] doubleValue]),Compact([task[@"inputTokens"] doubleValue]),Compact([task[@"outputTokens"] doubleValue])],50,65,9,Muted(),w-64);
    Text([task[@"unread"] boolValue]?@"点击查看 Codex 中的完成结果":(Safe(task[@"statusHeading"])?:Safe(task[@"activity"])?:@"正在处理任务"),12,86,10,accent,w-24);
    NSString *progress=[task[@"unread"] boolValue]?@"查看前会一直保留，关闭或重启悬浮窗也不会丢失。":Safe(task[@"progressText"]);
    if(progress.length){NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;
        [progress drawInRect:NSMakeRect(12,108,w-24,34) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:Muted(),NSParagraphStyleAttributeName:style}];}
    CGFloat x=w-102,y=34;
    NSUInteger frame=tick%12,kind=ChatHash(task)%12;
    if(kind==0){
        CGFloat travel=(frame%6)*4;
        DrawCharacter(task,tick,x+travel,y+4,2);
        for(int i=0;i<4;i++){CGFloat dotX=x+30+i*13;if(dotX>x+travel+24)FillPixel(dotX,y+15,3,3,accent);}
        FillPixel(x,y+32,82,2,[accent colorWithAlphaComponent:.3]);
    }else if(kind==1){
        CGFloat jump[]={0,0,4,8,12,16,16,12,8,4,0,0};
        DrawCharacter(task,tick,x+19,y+13-jump[frame],2);
        for(int i=0;i<4;i++){
            FillPixel(x+i*20,y+38,18,7,[accent colorWithAlphaComponent:.6]);
            FillPixel(x+i*20+2,y+40,14,2,accent);
        }
        FillPixel(x+54,y+2,15,13,accent);FillPixel(x+56,y+4,11,9,Ink());
        FillPixel(x+60,y+5,3,4,accent);FillPixel(x+60,y+11,3,2,accent);
    }else if(kind==2){
        CGFloat sway=frame<6?frame:12-frame;
        DrawCharacter(task,tick,x+24+sway,y+8+(frame%4<2?0:2),2);
        FillPixel(x+8,y+34,68,2,[accent colorWithAlphaComponent:.4]);
        for(int i=0;i<3;i++){CGFloat px=x+8+i*30,py=y+22-(frame+i*3)%16;
            FillPixel(px,py,2,5,[accent colorWithAlphaComponent:.7]);}
    }else if(kind==3){
        DrawCharacter(task,tick,x+27,y+8+(frame%6<3?0:2),2);
        for(int i=0;i<4;i++){
            CGFloat px=x+8+(i%2)*65,py=y+3+(i/2)*32;
            if((frame+i*3)%12<7){FillPixel(px-3,py,8,2,accent);FillPixel(px,py-3,2,8,accent);}
        }
    }else{
        CGFloat bob=(frame<6?frame:12-frame);
        CGFloat drift=(kind==5 || kind==9)?0:(frame%6)*2;
        DrawCharacter(task,tick,x+25+drift,y+8-bob,2);
        if(kind==8){
            for(int i=0;i<3;i++)FillPixel(x+36+i*3,y+32+((frame+i)%4),2,4,accent);
            for(int i=0;i<3;i++)FillPixel(x+5+i*24,y+(frame*3+i*7)%34,2,2,Muted());
        }else if(kind==4 || kind==10){
            for(int i=0;i<3;i++)if((frame+i)%4<2)FillPixel(x+4+i*31,y+6+(i*11)%26,3,3,accent);
        }else{
            FillPixel(x+9,y+36,68,2,[accent colorWithAlphaComponent:.35]);
            if(frame%6<3){FillPixel(x+9,y+25,3,6,accent);FillPixel(x+75,y+20,3,6,accent);}
        }
    }


}

@interface TaskRowButton:NSButton
@property NSDictionary *task;
@property NSUInteger tick;
@end
@implementation TaskRowButton
- (BOOL)isFlipped {return YES;}
- (BOOL)mouseDownCanMoveWindow {return NO;}
- (void)drawRect:(NSRect)dirty {DrawTaskCard(self.task,self.tick,self.bounds,self.highlighted);}
@end

@interface TaskDocumentView:NSView @end
@implementation TaskDocumentView
- (BOOL)isFlipped {return YES;}
- (BOOL)mouseDownCanMoveWindow {return NO;}
- (void)drawRect:(NSRect)dirty {if(!self.subviews.count){Text(@"暂无正在运行的任务",18,25,13,Mint(),360);Text(@"Codex 开始工作后会自动显示在这里",18,54,10,Muted(),370);}}
@end

@interface CompletionToastButton:NSButton
@property NSDictionary *task;
@property NSUInteger batchCount;
@end
@implementation CompletionToastButton
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(NSRect)dirty {
    [NSGraphicsContext.currentContext setShouldAntialias:NO];
    PixelBox(self.bounds,ChatColor(self.task));PixelBox(NSInsetRect(self.bounds,2,2),Ink());
    Text(self.task[@"title"]?:@"任务",16,10,12,ChatColor(self.task),410);
    NSString *output=Safe(self.task[@"completedText"]);
    if(!output.length)output=@"这轮已结束，输出文本尚未同步。点击打开对话查看。";
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;
    [output drawInRect:NSMakeRect(16,36,410,self.bounds.size.height-45) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:style}];
}
@end

@interface IslandApp:NSObject<NSApplicationDelegate>
@property IslandPanel *panel;
@property NSStatusItem *status;
@property PixelView *canvas;
@property NSScrollView *tasksScroll;
@property TaskDocumentView *tasksDocument;
@property NSString *navigationError;
@property NSTask *bridge;
@property NSPipe *pipe;
@property NSMutableData *buffer;
@property NSArray *tasks;
@property NSArray *todos;
@property NSMutableArray *finalLocks;
@property BOOL todoMode;
@property NSScrollView *todoScroll;
@property NSView *todoDocument;
@property NSButton *taskTab;
@property NSButton *todoTab;

@property NSTimer *timer;
@property BOOL watchMode;
@property BOOL userHidden;
@property NSTimeInterval lastReconcile;
@property NSTimeInterval lastHealthWrite;
@property int lockFD;
@property IslandPanel *toastPanel;
@property NSTimer *toastTimer;
@property NSMutableArray *completionQueue;
@property id globalClickMonitor;
@property id localClickMonitor;
@property NSSound *completionSound;
@property NSSound *finalSound;
@end
@implementation IslandApp
- (BOOL)codexRunning { return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.openai.codex"].count>0; }
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    self.lockFD=open([[directory stringByAppendingPathComponent:@"island.lock"] fileSystemRepresentation],O_CREAT|O_RDWR,0600);
    if(self.lockFD>=0 && flock(self.lockFD,LOCK_EX|LOCK_NB)!=0){close(self.lockFD);self.lockFD=-1;[NSApp terminate:nil];return;}
    NSString *lockPath=[directory stringByAppendingPathComponent:@"final-display.json"];
    NSData *locks=[NSData dataWithContentsOfFile:lockPath];
    NSArray *loaded=locks?[NSJSONSerialization JSONObjectWithData:locks options:0 error:nil]:nil;
    self.finalLocks=[loaded isKindOfClass:NSArray.class]?[loaded mutableCopy]:[NSMutableArray new];
    self.watchMode=[NSProcessInfo.processInfo.arguments containsObject:@"--watch"];
    self.panel=[[IslandPanel alloc]initWithContentRect:NSMakeRect(0,0,480,38) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.level=NSFloatingWindowLevel;self.panel.backgroundColor=NSColor.clearColor;self.panel.opaque=NO;
    self.panel.hasShadow=YES;self.panel.hidesOnDeactivate=NO;self.panel.movableByWindowBackground=YES;
    self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.canvas=[[PixelView alloc]initWithFrame:NSMakeRect(0,0,480,38)];self.panel.contentView=self.canvas;
    self.canvas.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSButton *header=[NSButton buttonWithTitle:@"" target:self action:@selector(expand:)];header.frame=NSMakeRect(44,5,430,28);header.bordered=NO;
    header.toolTip=@"展开运行任务与用量 · 拖动像素图标或边缘移动";header.accessibilityLabel=@"Codex Island：展开任务和用量";
    [self.canvas addSubview:header];
    self.tasksScroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(18,75,444,112)];
    self.tasksScroll.hasVerticalScroller=YES;self.tasksScroll.hasHorizontalScroller=NO;
    self.tasksScroll.autohidesScrollers=YES;self.tasksScroll.drawsBackground=NO;
    self.tasksScroll.scrollerStyle=NSScrollerStyleOverlay;self.tasksScroll.verticalLineScroll=TaskRowHeight;
    self.tasksDocument=[[TaskDocumentView alloc]initWithFrame:NSMakeRect(0,0,444,112)];
    self.tasksScroll.documentView=self.tasksDocument;self.tasksScroll.hidden=YES;
    [self.canvas addSubview:self.tasksScroll];
    self.taskTab=[PixelTabButton buttonWithTitle:@"任务" target:self action:@selector(selectTasks:)];
    self.todoTab=[PixelTabButton buttonWithTitle:@"待办" target:self action:@selector(selectTodos:)];
    self.taskTab.frame=NSMakeRect(18,44,96,28);self.todoTab.frame=NSMakeRect(122,44,142,28);
    self.taskTab.bordered=NO;self.todoTab.bordered=NO;
    self.taskTab.hidden=YES;self.todoTab.hidden=YES;
    [self.canvas addSubview:self.taskTab];[self.canvas addSubview:self.todoTab];
    self.todoScroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(18,75,444,112)];
    self.todoScroll.hasVerticalScroller=YES;self.todoScroll.drawsBackground=NO;self.todoScroll.autohidesScrollers=YES;
    self.todoDocument=[[TaskDocumentView alloc]initWithFrame:NSMakeRect(0,0,444,112)];
    self.todoScroll.documentView=self.todoDocument;self.todoScroll.hidden=YES;[self.canvas addSubview:self.todoScroll];
    self.status=[NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.status.button.image=[NSImage imageWithSystemSymbolName:@"rectangle.inset.filled" accessibilityDescription:@"Codex Island"];
    NSMenu *menu=[NSMenu new];
    NSArray *titles=@[@"显示 / 隐藏",@"打开 Codex",@"回到顶部",@"退出悬浮窗"];
    NSArray *selectors=@[@"toggle:",@"openCodex:",@"position:",@"quit:"];
    for(NSUInteger i=0;i<titles.count;i++){NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:titles[i] action:NSSelectorFromString(selectors[i]) keyEquivalent:@""];item.target=self;[menu addItem:item];}
    self.status.menu=menu;
    [self position:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceChanged:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceChanged:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    self.completionSound=[[NSSound alloc]initWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"step.wav"] byReference:YES];
    self.finalSound=[[NSSound alloc]initWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"complete.wav"] byReference:YES];
    __weak IslandApp *weakSelf=self;
    self.globalClickMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^(NSEvent *event){[weakSelf outsideClickAt:NSEvent.mouseLocation];}];
    self.localClickMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event){if(event.window!=weakSelf.panel && event.window!=weakSelf.toastPanel)[weakSelf outsideClickAt:NSEvent.mouseLocation];return event;}];
    NSMenuItem *sound=[[NSMenuItem alloc]initWithTitle:@"完成音效" action:@selector(toggleSound:) keyEquivalent:@""];sound.target=self;sound.state=[NSUserDefaults.standardUserDefaults boolForKey:@"SoundDisabled"]?NSControlStateValueOff:NSControlStateValueOn;[menu insertItem:sound atIndex:3];
    [self reconcile];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible { self.userHidden=NO;[self reconcile];return YES; }
- (void)workspaceChanged:(NSNotification *)notification {
    NSRunningApplication *app=notification.userInfo[NSWorkspaceApplicationKey];
    if([app.bundleIdentifier isEqual:@"com.openai.codex"]){self.userHidden=NO;[self reconcile];}
}
- (void)reconcile {
    BOOL shouldRun=!self.watchMode || [self codexRunning];
    self.status.visible=shouldRun;
    if(shouldRun){if(!self.userHidden)[self.panel orderFrontRegardless];[self startBridge];}
    else{[self.panel orderOut:nil];[self.toastPanel orderOut:nil];[self stopBridge];}
}
- (void)tick:(NSTimer *)timer {
    if(self.panel.visible){if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)self.canvas.tick++;[self.canvas setNeedsDisplay:YES];
        for(TaskRowButton *row in self.tasksDocument.subviews){row.tick=self.canvas.tick;if(NSIntersectsRect(row.frame,self.tasksDocument.visibleRect))[row setNeedsDisplay:YES];}}
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(now-self.lastReconcile>5){self.lastReconcile=now;[self reconcile];}
}
- (void)startBridge {
    if(self.bridge.running)return;
    NSString *script=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"monitor.py"];
    if(![NSFileManager.defaultManager fileExistsAtPath:script])return;
    self.bridge=[NSTask new];self.bridge.executableURL=[NSURL fileURLWithPath:@"/usr/bin/python3"];self.bridge.arguments=@[script];
    self.pipe=[NSPipe pipe];self.bridge.standardOutput=self.pipe;self.bridge.standardError=[NSFileHandle fileHandleWithNullDevice];self.buffer=[NSMutableData data];
    __weak IslandApp *weakSelf=self;
    self.pipe.fileHandleForReading.readabilityHandler=^(NSFileHandle *handle){
        NSData *data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}
        dispatch_async(dispatch_get_main_queue(), ^{IslandApp *owner=weakSelf;if(!owner)return;
            [owner.buffer appendData:data];
            while(YES){const char *bytes=owner.buffer.bytes;const char *end=memchr(bytes,'\n',owner.buffer.length);if(!end)break;
                NSUInteger length=end-bytes;NSData *line=[owner.buffer subdataWithRange:NSMakeRange(0,length)];
                [owner.buffer replaceBytesInRange:NSMakeRange(0,length+1) withBytes:NULL length:0];
                NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:line options:0 error:nil];if([snapshot isKindOfClass:NSDictionary.class])[owner updateSnapshot:snapshot];
            }
            if(owner.buffer.length>8*1024*1024)[owner.buffer setLength:0];
        });
    };
    NSError *error=nil;if(![self.bridge launchAndReturnError:&error]){self.canvas.snapshot=@{@"errors":@[@"监控进程启动失败"]};[self.canvas setNeedsDisplay:YES];}
}
- (void)stopBridge {self.pipe.fileHandleForReading.readabilityHandler=nil;if(self.bridge.running)[self.bridge terminate];self.bridge=nil;}
- (void)outsideClickAt:(NSPoint)point {if(self.canvas.expanded && self.panel.visible && !NSPointInRect(point,self.panel.frame))[self expand:nil];}
- (void)toggleSound:(NSMenuItem *)item {BOOL disabled=![NSUserDefaults.standardUserDefaults boolForKey:@"SoundDisabled"];[NSUserDefaults.standardUserDefaults setBool:disabled forKey:@"SoundDisabled"];item.state=disabled?NSControlStateValueOff:NSControlStateValueOn;}
- (void)updateSnapshot:(NSDictionary *)snapshot {
    self.canvas.snapshot=snapshot;
    [self refreshTodos];
    NSArray *active=Safe(snapshot[@"tasks"]) ?: @[];
    NSArray *previous=self.tasks?:@[];
    CGFloat previousOffset=self.tasksScroll.contentView.bounds.origin.y;
    NSUInteger anchorIndex=(NSUInteger)MAX(0,floor(previousOffset/TaskRowHeight));
    NSString *anchorID=anchorIndex<previous.count?(previous[anchorIndex][@"listId"]?:previous[anchorIndex][@"id"]):nil;
    self.tasks=active;
    for(NSDictionary *event in snapshot[@"completions"])if([event[@"soundKind"] isEqual:@"final"] && ![event[@"isDemo"] boolValue]){
        if(!self.finalLocks)self.finalLocks=[NSMutableArray new];
        NSIndexSet *duplicates=[self.finalLocks indexesOfObjectsPassingTest:^BOOL(NSDictionary *old,NSUInteger idx,BOOL *stop){return [ChatKey(old) isEqual:ChatKey(event)];}];
        [self.finalLocks removeObjectsAtIndexes:duplicates];[self.finalLocks addObject:event];[self saveFinalLocks];
    }
    [self selectMainCharacter];
    NSMutableArray *oldIDs=[NSMutableArray new],*newIDs=[NSMutableArray new];
    for(NSDictionary *task in previous)[oldIDs addObject:task[@"listId"]?:task[@"id"]];
    for(NSDictionary *task in active)[newIDs addObject:task[@"listId"]?:task[@"id"]];
    if(![oldIDs isEqual:newIDs]){
        for(NSView *row in self.tasksDocument.subviews.copy)[row removeFromSuperview];
        for(NSDictionary *task in active){
            TaskRowButton *row=[[TaskRowButton alloc]initWithFrame:NSZeroRect];
            row.title=@"";row.bordered=NO;row.buttonType=NSButtonTypeMomentaryPushIn;
            row.task=task;row.target=self;row.action=@selector(openTask:);
            [self.tasksDocument addSubview:row];
        }
    }
    [self layoutTasks];
    for(NSUInteger i=0;i<active.count;i++){
        TaskRowButton *row=(TaskRowButton *)self.tasksDocument.subviews[i];row.task=active[i];row.tick=self.canvas.tick;
        row.toolTip=[NSString stringWithFormat:@"%@ · 点击打开对应 Codex 页面",active[i][@"title"]?:@"Codex 任务"];
        row.accessibilityLabel=row.toolTip;[row setNeedsDisplay:YES];
    }
    CGFloat newOffset=previousOffset;
    if(anchorID)for(NSUInteger i=0;i<active.count;i++)if([(active[i][@"listId"]?:active[i][@"id"]) isEqual:anchorID]){newOffset=i*TaskRowHeight+fmod(previousOffset,TaskRowHeight);break;}
    newOffset=MAX(0,MIN(newOffset,self.tasksDocument.frame.size.height-self.tasksScroll.contentSize.height));
    [self.tasksScroll.contentView scrollToPoint:NSMakePoint(0,newOffset)];[self.tasksScroll reflectScrolledClipView:self.tasksScroll.contentView];
    if([Safe(snapshot[@"completions"]) count])[self showCompletionToast:snapshot[@"completions"]];
    self.status.button.toolTip=[NSString stringWithFormat:@"Codex Island · %@ 个运行任务",snapshot[@"runningCount"]?:@0];
    [self.canvas setNeedsDisplay:YES];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(now-self.lastHealthWrite>10){
        self.lastHealthWrite=now;
        NSDictionary *health=@{@"version":@2,@"build":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"development",@"ui":@"task-list",@"outsideClickMonitoring":@(self.globalClickMonitor!=nil && self.localClickMonitor!=nil),@"completionSoundLoaded":@(self.completionSound!=nil),@"finalSoundLoaded":@(self.finalSound!=nil),@"selectedChatId":ChatKey(self.canvas.selected),@"finalDisplayCount":@(self.finalLocks.count),@"todoCount":@(self.todos.count),@"listedTaskCount":@(self.tasksDocument.subviews.count),@"pid":@(NSProcessInfo.processInfo.processIdentifier),@"watchMode":@(self.watchMode),@"windowVisible":@(self.panel.visible),@"codexRunning":@([self codexRunning]),@"runningCount":snapshot[@"runningCount"]?:@0,@"unreadCount":snapshot[@"unreadCount"]?:@0,@"lastSnapshotAt":@(now)};
        NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island/health.json"];
        [[NSJSONSerialization dataWithJSONObject:health options:0 error:nil] writeToFile:path atomically:YES];
    }
}
- (void)layoutTasks {
    ((PixelTabButton *)self.taskTab).activeTab=!self.todoMode;((PixelTabButton *)self.todoTab).activeTab=self.todoMode;
    [self.taskTab setNeedsDisplay:YES];[self.todoTab setNeedsDisplay:YES];
    ((PixelTabButton *)self.taskTab).accent=ChatColor(self.canvas.selected);((PixelTabButton *)self.todoTab).accent=ChatColor(self.canvas.selected);
    CGFloat maximum=592;
    if(self.panel.screen)maximum=MIN(maximum,self.panel.screen.visibleFrame.size.height-178);
    CGFloat expandedHeight=MIN(maximum,144+MAX((NSUInteger)1,self.todoMode?self.todos.count:self.tasks.count)*(self.todoMode?64:TaskRowHeight));
    if(self.canvas.expanded && self.panel){NSRect old=self.panel.frame;[self.panel setFrame:NSMakeRect(old.origin.x,NSMaxY(old)-expandedHeight,480,expandedHeight) display:YES animate:NO];}
    CGFloat viewport=MAX(50,expandedHeight-144);
    self.tasksScroll.frame=NSMakeRect(18,75,444,viewport);
    CGFloat width=self.tasksScroll.contentSize.width;
    self.tasksDocument.frame=NSMakeRect(0,0,width,MAX(viewport,self.tasks.count*TaskRowHeight));
    NSUInteger index=0;for(TaskRowButton *row in self.tasksDocument.subviews){row.frame=NSMakeRect(0,index++*TaskRowHeight,width,TaskRowHeight);}
    self.tasksScroll.hidden=!self.canvas.expanded || self.todoMode;
    self.todoScroll.hidden=!self.canvas.expanded || !self.todoMode;
    self.taskTab.hidden=!self.canvas.expanded;self.todoTab.hidden=!self.canvas.expanded;
    self.todoScroll.frame=NSMakeRect(18,75,444,viewport);
    self.todoDocument.frame=NSMakeRect(0,0,self.todoScroll.contentSize.width,MAX(viewport,self.todos.count*64));
    NSUInteger todoIndex=0;for(NSView *row in self.todoDocument.subviews)row.frame=NSMakeRect(8,todoIndex++*64+8,self.todoScroll.contentSize.width-16,48);

}
- (void)saveFinalLocks {
    if([NSProcessInfo.processInfo.arguments containsObject:@"--test-list"])return;
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island/final-display.json"];
    [[NSJSONSerialization dataWithJSONObject:self.finalLocks?:@[] options:0 error:nil] writeToFile:path atomically:YES];
}
- (void)selectMainCharacter {
    NSDictionary *selected=self.finalLocks.lastObject;
    if(!selected)for(NSDictionary *task in self.tasks){
        if(![@[@"running",@"waiting"] containsObject:task[@"status"]])continue;
        if(!selected || [task[@"activatedAt"] doubleValue]>[selected[@"activatedAt"] doubleValue])selected=task;
    }
    self.canvas.selected=selected;[self.canvas setNeedsDisplay:YES];
}
- (void)refreshTodos {
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island/todos.json"];
    NSData *data=[NSData dataWithContentsOfFile:path];
    NSArray *items=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@[];
    if(![items isKindOfClass:NSArray.class])return;
    if([self.todos isEqual:items])return;
    self.todos=items;
    NSUInteger pending=0;for(NSDictionary *item in items)if(![item[@"done"] boolValue])pending++;
    self.todoTab.title=[NSString stringWithFormat:@"待办 (%lu)",(unsigned long)pending];
    for(NSView *row in self.todoDocument.subviews.copy)[row removeFromSuperview];
    for(NSDictionary *item in items){
        NSButton *row=[NSButton checkboxWithTitle:item[@"title"]?:@"待办" target:self action:@selector(toggleTodo:)];
        row.identifier=item[@"id"];row.state=[item[@"done"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;
        row.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        row.toolTip=[NSString stringWithFormat:@"%@\n%@",item[@"title"]?:@"",item[@"note"]?:@""];
        [self.todoDocument addSubview:row];
    }
    if(!items.count){NSTextField *empty=[NSTextField labelWithString:@"暂无待办 · 在对话中说“添加待办…”"];empty.textColor=Muted();[self.todoDocument addSubview:empty];}
}
- (void)selectTasks:(id)sender {self.todoMode=NO;[self layoutTasks];}
- (void)selectTodos:(id)sender {self.todoMode=YES;[self refreshTodos];[self layoutTasks];}
- (void)toggleTodo:(NSButton *)sender {
    NSTask *command=[NSTask new];command.executableURL=[NSURL fileURLWithPath:@"/usr/bin/python3"];
    command.arguments=@[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"todo.py"],@"toggle",sender.identifier];
    command.standardOutput=[NSPipe pipe];command.standardError=[NSPipe pipe];
    NSError *error=nil;if([command launchAndReturnError:&error]){[command waitUntilExit];if(command.terminationStatus!=0)NSBeep();}else NSBeep();
    [self refreshTodos];[self layoutTasks];
}
- (void)showCompletionToast:(NSArray *)completions {
    if(!self.completionQueue)self.completionQueue=[NSMutableArray new];
    for(NSDictionary *event in completions)if(![event[@"quiet"] boolValue])[self.completionQueue addObject:event];
    if(self.toastPanel.visible || !self.completionQueue.count)return;
    NSDictionary *next=self.completionQueue.firstObject;[self.completionQueue removeObjectAtIndex:0];
    completions=@[next];
    [self.toastTimer invalidate];
    if(!self.toastPanel){self.toastPanel=[[IslandPanel alloc]initWithContentRect:NSMakeRect(0,0,444,150) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        self.toastPanel.level=NSFloatingWindowLevel;self.toastPanel.backgroundColor=NSColor.clearColor;self.toastPanel.opaque=NO;self.toastPanel.hasShadow=YES;self.toastPanel.hidesOnDeactivate=NO;self.toastPanel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;}
    CompletionToastButton *toast=[[CompletionToastButton alloc]initWithFrame:NSMakeRect(0,0,444,150)];toast.task=completions.firstObject;toast.batchCount=completions.count;toast.title=@"";toast.bordered=NO;toast.target=self;toast.action=@selector(openCompletionToast:);toast.accessibilityLabel=@"任务已完成，点击查看";self.toastPanel.contentView=toast;
    NSRect frame=self.panel.frame,screen=(self.panel.screen?:NSScreen.mainScreen).visibleFrame;
    CGFloat y=NSMinY(frame)-158;
    if(y<NSMinY(screen)+8)y=NSMinY(screen)+8;
    [self.toastPanel setFrame:NSMakeRect(NSMinX(frame)+18,y,444,150) display:YES];[self.toastPanel orderFrontRegardless];
    BOOL final=[next[@"soundKind"] isEqual:@"final"];
    NSSound *sound=final?self.finalSound:self.completionSound;
    BOOL muted=[NSUserDefaults.standardUserDefaults boolForKey:@"SoundDisabled"] && ![next[@"isDemo"] boolValue];
    BOOL played=NO;if(!muted){[self.completionSound stop];[self.finalSound stop];played=[sound play];}
    NSString *eventID=Safe(next[@"eventId"]);
    if(eventID.length){
        NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island/notification-receipts"];
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *receipt=@{@"eventId":eventID,@"soundKind":final?@"final":@"step",@"played":@(played),@"muted":@(muted),@"presentedAt":@(NSDate.date.timeIntervalSince1970)};
        [[NSJSONSerialization dataWithJSONObject:receipt options:0 error:nil] writeToFile:[directory stringByAppendingPathComponent:[eventID stringByAppendingString:@".json"]] atomically:YES];
    }

    self.toastTimer=[NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(hideCompletionToast:) userInfo:nil repeats:NO];
}
- (void)hideCompletionToast:(id)sender {[self.toastPanel orderOut:nil];[self showCompletionToast:@[]];}
- (void)openCompletionToast:(CompletionToastButton *)sender {if(![sender.task[@"isDemo"] boolValue])[self openTaskRecord:sender.task];[self.toastTimer invalidate];[self hideCompletionToast:nil];}
- (void)markCompletionViewed:(NSDictionary *)task {
    NSArray *keys=Safe(task[@"completionKeys"]);
    if(!keys.count && [Safe(task[@"completionKey"]) length])keys=@[task[@"completionKey"]];
    if(!keys.count)return;
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Island/read-receipts"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    for(NSString *key in keys){NSString *path=[directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".json"]];[[NSJSONSerialization dataWithJSONObject:@{@"completionKey":key} options:0 error:nil] writeToFile:path atomically:YES];}
}
- (void)openTaskRecord:(NSDictionary *)task {
    NSURL *url=ThreadURL(task[@"navigateId"]?:task[@"rootId"]?:task[@"id"]);if(!url)return;
    if(![self openTaskURL:url]){
        self.navigationError=@"无法打开 Codex，请确认应用已安装";self.status.button.toolTip=self.navigationError;NSBeep();
    }else{
        NSIndexSet *viewed=[self.finalLocks indexesOfObjectsPassingTest:^BOOL(NSDictionary *locked,NSUInteger idx,BOOL *stop){return [ChatKey(locked) isEqual:ChatKey(task)];}];
        [self.finalLocks removeObjectsAtIndexes:viewed];[self saveFinalLocks];[self selectMainCharacter];[self layoutTasks];
        [self markCompletionViewed:task];if(self.canvas.expanded)[self expand:nil];
    }
}
- (void)openTask:(TaskRowButton *)sender {[self openTaskRecord:sender.task];}
- (BOOL)openTaskURL:(NSURL *)url {return [NSWorkspace.sharedWorkspace openURL:url];}
- (void)expand:(id)sender {
    self.canvas.expanded=!self.canvas.expanded;
    if(self.canvas.expanded)[self layoutTasks];
    else{NSRect old=self.panel.frame;[self.panel setFrame:NSMakeRect(old.origin.x,NSMaxY(old)-38,480,38) display:YES animate:NO];self.tasksScroll.hidden=YES;self.todoScroll.hidden=YES;self.taskTab.hidden=YES;self.todoTab.hidden=YES;}
    [self.canvas setNeedsDisplay:YES];
}
- (void)toggle:(id)sender {self.userHidden=self.panel.visible;if(self.userHidden)[self.panel orderOut:nil];else[self.panel orderFrontRegardless];}
- (void)position:(id)sender {NSRect screen=NSScreen.mainScreen.visibleFrame;[self.panel setFrameTopLeftPoint:NSMakePoint(NSMidX(screen)-240,NSMaxY(screen)-6)];}
- (void)openCodex:(id)sender {
    NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.openai.codex"];
    if(url)[NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
}
- (void)quit:(id)sender {[NSApp terminate:nil];}
- (void)applicationWillTerminate:(NSNotification *)notification {[self.timer invalidate];[self.toastTimer invalidate];[self.toastPanel orderOut:nil];if(self.globalClickMonitor)[NSEvent removeMonitor:self.globalClickMonitor];if(self.localClickMonitor)[NSEvent removeMonitor:self.localClickMonitor];[self stopBridge];if(self.lockFD>=0)close(self.lockFD);}
@end

@interface TestVisiblePanel:IslandPanel @end
@implementation TestVisiblePanel
- (BOOL)isVisible {return YES;}
@end
@interface TestIslandApp:IslandApp
@property NSString *openedID;
@property NSURL *openedURL;
@end
@implementation TestIslandApp
- (void)openTask:(TaskRowButton *)sender {self.openedID=sender.task[@"id"];}
- (BOOL)openTaskURL:(NSURL *)url {self.openedURL=url;return YES;}
@end
static int TestTaskList(void) {
    [NSApplication sharedApplication];
    TestIslandApp *owner=[TestIslandApp new];
    owner.canvas=[[PixelView alloc]initWithFrame:NSMakeRect(0,0,480,592)];owner.canvas.expanded=YES;
    owner.tasksScroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(18,75,444,448)];owner.tasksScroll.hasVerticalScroller=YES;
    owner.tasksDocument=[[TaskDocumentView alloc]initWithFrame:NSMakeRect(0,0,444,448)];owner.tasksScroll.documentView=owner.tasksDocument;
    owner.lastHealthWrite=NSDate.date.timeIntervalSince1970+3600;
    NSMutableArray *tasks=[NSMutableArray new];
    for(int i=0;i<40;i++)[tasks addObject:@{@"id":[NSString stringWithFormat:@"task-%d",i],@"title":@"同名任务",@"status":@"running",@"phase":@"working",@"tokens":@0}];
    [owner updateSnapshot:@{@"tasks":tasks,@"runningCount":@40}];
    NSCAssert(owner.tasksDocument.subviews.count==40,@"Duplicate titles must keep all rows");
    NSCAssert(owner.tasksDocument.frame.size.height>owner.tasksScroll.contentSize.height,@"Long list must scroll");
    TaskRowButton *row=(TaskRowButton *)owner.tasksDocument.subviews[7];[row performClick:nil];
    NSCAssert([owner.openedID isEqual:@"task-7"],@"Click must open exact task ID");
    NSCAssert([ThreadURL(@"abc/a ?#").absoluteString isEqual:@"codex://threads/abc%2Fa%20%3F%23"],@"Task IDs must be URL encoded");
    NSCAssert(ThreadURL(@"")==nil,@"Empty ID must not navigate");
    [owner openTaskRecord:@{@"id":@"child",@"rootId":@"parent"}];
    NSCAssert([owner.openedURL.absoluteString isEqual:@"codex://threads/parent"],@"Child results must open the user's main chat");
    [owner.tasksScroll.contentView scrollToPoint:NSMakePoint(0,7*TaskRowHeight+10)];
    NSMutableArray *reordered=[tasks mutableCopy];[reordered insertObject:@{@"id":@"new",@"title":@"新任务",@"status":@"running"} atIndex:0];
    [owner updateSnapshot:@{@"tasks":reordered,@"runningCount":@41}];
    NSCAssert(fabs(owner.tasksScroll.contentView.bounds.origin.y-(8*TaskRowHeight+10))<1,@"Refresh must retain visible task anchor");
    NSArray *reverse=tasks.reverseObjectEnumerator.allObjects;
    [owner updateSnapshot:@{@"tasks":reverse,@"runningCount":@40}];
    [(TaskRowButton *)owner.tasksDocument.subviews[0] performClick:nil];
    NSCAssert([owner.openedID isEqual:@"task-39"],@"Reordered click must use stable ID");
    for(int n=12;n>=0;n--){NSArray *subset=[tasks subarrayWithRange:NSMakeRange(0,n)];[owner updateSnapshot:@{@"tasks":subset,@"runningCount":@(n)}];NSCAssert(owner.tasksDocument.subviews.count==n,@"Shrinking list mismatch");}
    [owner updateSnapshot:@{@"tasks":@[],@"recentTasks":tasks,@"runningCount":@0}];
    NSCAssert(owner.tasksDocument.subviews.count==0,@"Completed history must not appear as running");
    [owner updateSnapshot:@{@"tasks":tasks,@"runningCount":@40}];
    NSCAssert(owner.tasksDocument.subviews.count==40,@"Growing list mismatch");
    NSDictionary *activeRound=tasks[0];
    NSMutableDictionary *unreadRound=[activeRound mutableCopy];unreadRound[@"status"]=@"completed";unreadRound[@"phase"]=@"done";unreadRound[@"unread"]=@YES;unreadRound[@"completionKey"]=@"task-0:old-turn";unreadRound[@"listId"]=@"completed:task-0:old-turn";
    [owner updateSnapshot:@{@"tasks":@[activeRound,unreadRound],@"runningCount":@1,@"unreadCount":@1}];
    NSCAssert(owner.tasksDocument.subviews.count==2,@"New round must not overwrite unread completed round");
    NSCAssert([((TaskRowButton *)owner.tasksDocument.subviews[1]).task[@"unread"] boolValue],@"Unread completed card must remain visible");
    CompletionToastButton *toast=[[CompletionToastButton alloc]initWithFrame:NSMakeRect(0,0,444,150)];toast.task=unreadRound;toast.batchCount=1;NSCAssert([toast.task[@"completionKey"] isEqual:@"task-0:old-turn"],@"Toast must retain completion identity");
    owner.panel=[[TestVisiblePanel alloc]initWithContentRect:NSMakeRect(100,100,480,592) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    owner.canvas.expanded=YES;
    [owner outsideClickAt:NSMakePoint(150,150)];NSCAssert(owner.canvas.expanded,@"Inside click must preserve expansion");
    [owner outsideClickAt:NSMakePoint(10,10)];NSCAssert(!owner.canvas.expanded && owner.tasksScroll.hidden,@"Outside click must collapse panel");
    [owner outsideClickAt:NSMakePoint(10,10)];NSCAssert(!owner.canvas.expanded,@"Outside click must never reopen panel");
    NSDictionary *older=@{@"id":@"root-a",@"status":@"running",@"activatedAt":@10};
    NSDictionary *newer=@{@"id":@"root-b",@"status":@"running",@"activatedAt":@20};
    owner.tasks=@[older,newer];owner.finalLocks=[NSMutableArray new];[owner selectMainCharacter];
    NSCAssert([ChatKey(owner.canvas.selected) isEqual:@"root-b"],@"Newest activation must win independent of list order");
    [owner.finalLocks addObject:@{@"id":@"root-a",@"soundKind":@"final"}];[owner selectMainCharacter];
    NSCAssert([ChatKey(owner.canvas.selected) isEqual:@"root-a"],@"Final completion must hold display over active work");
    [owner.finalLocks removeAllObjects];[owner selectMainCharacter];
    NSCAssert([ChatKey(owner.canvas.selected) isEqual:@"root-b"],@"Viewed completion must return to running task");
    NSCAssert(ChatHash(@{@"id":@"child",@"rootId":@"root-a"})==ChatHash(older),@"Child and root must share identity");
    puts("Character selection passed: newest activation, final hold, release, stable root identity.");
    NSSound *sound=[[NSSound alloc]initWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"step.wav"] byReference:YES];
    NSCAssert(sound && sound.duration>0 && sound.duration<2,@"Completion sound must decode correctly");
    puts("Task list regression passed: 40 duplicate titles, scrolling, scroll anchor, task click, URL encoding, reorder, shrink, empty, grow.");
    return 0;
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSArray *arguments=NSProcessInfo.processInfo.arguments;
        if([arguments containsObject:@"--test-list"])return TestTaskList();
        NSUInteger render=[arguments indexOfObject:@"--render"];
        if(render!=NSNotFound && arguments.count>render+2){
            NSData *data=[NSData dataWithContentsOfFile:arguments[render+1]];NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *tasks=Safe(snapshot[@"tasks"])?:@[];
            CGFloat height=MIN(592,144+MAX((NSUInteger)1,tasks.count)*TaskRowHeight);
            PixelView *view=[[PixelView alloc]initWithFrame:NSMakeRect(0,0,480,height)];view.expanded=YES;view.snapshot=snapshot;view.selected=tasks.firstObject;view.tick=2;
            NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:960 pixelsHigh:(NSInteger)(height*2) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context.CGContext flipped:YES]];
            CGContextScaleCTM(context.CGContext,2,2);CGContextTranslateCTM(context.CGContext,0,height);CGContextScaleCTM(context.CGContext,1,-1);[view drawRect:view.bounds];
            CGContextSaveGState(context.CGContext);CGContextClipToRect(context.CGContext,CGRectMake(18,75,444,height-144));
            CGContextTranslateCTM(context.CGContext,18,75);
            if(!tasks.count){TaskDocumentView *empty=[[TaskDocumentView alloc]initWithFrame:NSMakeRect(0,0,444,112)];[empty drawRect:empty.bounds];}
            for(NSUInteger i=0;i<tasks.count;i++){if(i*TaskRowHeight>=height-144)break;
                CGContextSaveGState(context.CGContext);CGContextTranslateCTM(context.CGContext,0,i*TaskRowHeight);
                DrawTaskCard(tasks[i],2,NSMakeRect(0,0,444,TaskRowHeight),NO);CGContextRestoreGState(context.CGContext);
            }
            CGContextRestoreGState(context.CGContext);[NSGraphicsContext restoreGraphicsState];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:arguments[render+2] atomically:YES];return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;IslandApp *delegate=[IslandApp new];app.delegate=delegate;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];[app run];
    }
    return 0;
}
